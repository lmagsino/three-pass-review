#!/usr/bin/env node
// Review tier and merge gate for a pull request.
//
// 1. Tier: decides whether the PR gets a light or a deep human review, from
//    .github/review-policy.yml on the PR's BASE branch, so a PR can't loosen
//    the rules for its own review. Automation can raise a tier, never lower it.
// 2. Gate: publishes a `review-gate` commit status on the PR's head commit.
//      light: passes once the light review (pass 2) is clean on this exact commit
//      deep:  passes once enough people approved this exact commit
//    Make `review-gate` a required status check to enforce it.
//
// Runs from .github/workflows/review-tier.yml on `pull_request_target` and on
// `workflow_run` (after the light review or a submitted review). It reads the
// PR through the API and never checks out or runs PR code. It is the only
// thing that sets the tier labels.
//
// Local dry run (no network, no token):
//   node review-tier.mjs --dry-run --policy policy.json --files files.json \
//     [--labels "escalate/deep,bug"] [--author-association MEMBER] [--changed-files 12] \
//     [--fork] [--light clean|escalated|failed|none] [--approvals 1] [--json]
//
// files.json is the array returned by GET /repos/{owner}/{repo}/pulls/{n}/files
// (only filename, previous_filename, status, additions and deletions are used).

import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { execFileSync } from 'node:child_process';
import { pathToFileURL } from 'node:url';

export const MARKER = '<!-- review-tier -->';
export const LIGHT_MARKER = /^<!-- light-review(?: sha=([0-9a-f]{7,40}))?(?: result=(clean|escalated|failed))? -->/;
const STATUS_CONTEXT = 'review-gate';

// Changes to the review setup itself are always deep, whatever the policy
// says. Otherwise a PR could quietly weaken the reviewers that review it.
// Includes every place Copilot and Claude read instructions, skills and agents from.
export const REVIEW_MACHINERY = [
  '.github/workflows/**',
  '.github/review-policy.yml',
  '.github/scripts/**',
  '.github/review/**',
  '.github/copilot-instructions.md',
  '.github/instructions/**',
  '.github/skills/**',
  '.github/agents/**',
  'CODEOWNERS',
  '.claude/**',
  '.agents/**',
  'CLAUDE.md',
  'AGENTS.md',
  'REVIEW.md',
  'GEMINI.md',
];

const DEFAULTS = {
  labels: {
    light: 'tier/light',
    deep: 'tier/deep',
    escalate: 'escalate/deep',
    split: 'needs-split',
    skip_light: 'skip-light-review',
  },
  ignore_for_size: [],
  sensitive_paths: [],
  dependency_files: [],
  quality_gate_files: [],
  test_paths: [],
  thresholds: {
    deep_changed_lines: 400,
    split_changed_lines: 1000,
    deep_files: 30,
    deep_top_level_areas: 3,
    max_ignored_lines: 5000,
  },
  rules: {
    deleted_source_files_are_deep: true,
    deleted_tests_are_deep: true,
    dependency_changes_are_deep: true,
    quality_gate_changes_are_deep: true,
    first_time_contributors_are_deep: true,
    fork_prs_are_deep: true,
  },
  deep_review: { min_approvals: 2 },
  escalation: { removable_by: ['admin', 'maintain'] },
  first_time_associations: ['FIRST_TIME_CONTRIBUTOR', 'FIRST_TIMER', 'NONE'],
};

// ---------------------------------------------------------------------------
// Glob matching (gitignore / CODEOWNERS style, no dependencies)
//   *   any characters except '/'
//   **  any characters including '/'; '**/' also matches zero folders
//   ?   one character except '/'
//   A pattern with no '/' matches at any depth ("CODEOWNERS", "*.lock").
//   A leading '/' anchors to the repo root; a trailing '/' means "everything under".
// ---------------------------------------------------------------------------
const regexCache = new Map();

export function globToRegExp(glob) {
  if (regexCache.has(glob)) return regexCache.get(glob);
  let g = String(glob).trim();
  if (g.startsWith('/')) g = g.slice(1);
  if (g.endsWith('/')) g += '**';
  if (!g.includes('/')) g = '**/' + g;
  let re = '';
  for (let i = 0; i < g.length; i++) {
    const c = g[i];
    if (c === '*') {
      if (g[i + 1] === '*') {
        const atSegmentStart = i === 0 || g[i - 1] === '/';
        if (atSegmentStart && g[i + 2] === '/') {
          re += '(?:.*/)?';
          i += 2;
        } else {
          re += '.*';
          i += 1;
        }
      } else {
        re += '[^/]*';
      }
    } else if (c === '?') {
      re += '[^/]';
    } else {
      re += c.replace(/[.+^${}()|[\]\\]/g, '\\$&');
    }
  }
  const compiled = new RegExp('^' + re + '$');
  regexCache.set(glob, compiled);
  return compiled;
}

export function matchAny(path, globs = []) {
  return globs.some((glob) => globToRegExp(glob).test(path));
}

export function withDefaults(policy = {}) {
  return {
    ...DEFAULTS,
    ...policy,
    labels: { ...DEFAULTS.labels, ...(policy.labels || {}) },
    thresholds: { ...DEFAULTS.thresholds, ...(policy.thresholds || {}) },
    rules: { ...DEFAULTS.rules, ...(policy.rules || {}) },
    deep_review: { ...DEFAULTS.deep_review, ...(policy.deep_review || {}) },
    escalation: { ...DEFAULTS.escalation, ...(policy.escalation || {}) },
  };
}

const plural = (n, word) => `${n} ${word}${n === 1 ? '' : 's'}`;
const fmt = (n) => Number(n).toLocaleString('en-US');
// File names come from the PR, so they can't be allowed to break out of the
// code span (and code spans don't trigger @mentions).
export const code = (s) => '`' + String(s).replace(/[`\r\n]/g, '?') + '`';
const short = (sha) => String(sha || '').slice(0, 7);

function listPaths(paths, max = 3) {
  const shown = paths.slice(0, max).map(code).join(', ');
  return paths.length > max ? `${shown} and ${paths.length - max} more` : shown;
}

// ---------------------------------------------------------------------------
// The tier decision. Pure function: easy to test, no network.
// ---------------------------------------------------------------------------
export function decideTier({
  files,
  policy,
  labels = [],
  authorAssociation = '',
  changedFilesTotal,
  isFork = false,
}) {
  const p = withDefaults(policy);
  const reasons = [];
  const owners = new Set();
  const add = (rule, text) => reasons.push({ rule, text });

  // A renamed file is checked under its old and new path, so moving code out
  // of a sensitive folder doesn't dodge the rules.
  const pathsOf = (f) => [f.filename, f.previous_filename].filter(Boolean);
  const touching = (globs) =>
    files.filter((f) => pathsOf(f).some((x) => matchAny(x, globs))).map((f) => f.filename);
  const isTestPath = (x) => matchAny(x, p.test_paths);
  const isIgnored = (x) => matchAny(x, p.ignore_for_size);

  // 1. Escalation is sticky.
  if (labels.includes(p.labels.escalate)) {
    add(
      'escalated',
      `Escalated with the ${code(p.labels.escalate)} label, by the light review or a person. ` +
        'Automation never removes this label; only a maintainer can, with a comment saying why.'
    );
  }
  if (labels.includes(p.labels.skip_light)) {
    add('no-light-review', `Has the ${code(p.labels.skip_light)} label. The light tier needs a clean light review.`);
  }
  if (isFork && p.rules.fork_prs_are_deep) {
    add('fork', 'Comes from a fork. The light review doesn\'t run on forks, so there\'s no clean light review to rely on.');
  }

  // 2. The review setup itself.
  const machinery = touching(REVIEW_MACHINERY);
  if (machinery.length) {
    add('review-machinery', `Changes the review setup itself: ${listPaths(machinery)}.`);
  }

  // 3. Core / sensitive paths from the policy.
  for (const entry of p.sensitive_paths) {
    const patterns = [].concat(entry.pattern || entry.patterns || []);
    const hit = touching(patterns);
    if (!hit.length) continue;
    [].concat(entry.owners || []).filter(Boolean).forEach((o) => owners.add(o));
    const why = entry.why ? ` (${entry.why})` : '';
    add('sensitive-path', `Touches ${patterns.map(code).join(', ')}${why}: ${listPaths(hit)}.`);
  }

  // 4. Tests and quality gates. Weakening the checks is how bad changes get green.
  //    Renaming a test to something that isn't a test counts as deleting it.
  if (p.rules.deleted_tests_are_deep) {
    const goneTests = files
      .filter(
        (f) =>
          (f.status === 'removed' && isTestPath(f.filename)) ||
          (f.status === 'renamed' && f.previous_filename && isTestPath(f.previous_filename) && !isTestPath(f.filename))
      )
      .map((f) => f.previous_filename || f.filename);
    if (goneTests.length) add('deleted-tests', `Deletes or renames away tests: ${listPaths(goneTests)}.`);
  }
  if (p.rules.quality_gate_changes_are_deep) {
    const gates = touching(p.quality_gate_files);
    if (gates.length) {
      add('quality-gate', `Changes lint, test or coverage config: ${listPaths(gates)}. Check nothing was loosened.`);
    }
  }

  // 5. Deleted source files: whatever called them may still exist. Moving a
  //    source file into a generated/ignored path counts as deleting it.
  if (p.rules.deleted_source_files_are_deep) {
    const goneSource = files
      .filter(
        (f) =>
          (f.status === 'removed' && !isTestPath(f.filename) && !isIgnored(f.filename)) ||
          (f.status === 'renamed' && f.previous_filename && !isIgnored(f.previous_filename) && isIgnored(f.filename))
      )
      .map((f) => f.previous_filename || f.filename);
    if (goneSource.length) {
      add('deleted-source', `Deletes source files (does anything still call them?): ${listPaths(goneSource)}.`);
    }
  }

  // 6. Dependencies.
  if (p.rules.dependency_changes_are_deep) {
    const deps = touching(p.dependency_files);
    if (deps.length) add('dependencies', `Changes dependencies: ${listPaths(deps)}.`);
  }

  // 7. Size and spread. Lines in generated files and lockfiles don't count,
  //    but those files still count toward the file count and spread, and a
  //    very large "generated" change is suspicious in itself.
  const counted = files.filter((f) => !isIgnored(f.filename));
  const lines = (list) => list.reduce((n, f) => n + (f.additions || 0) + (f.deletions || 0), 0);
  const changedLines = lines(counted);
  const ignoredLines = lines(files) - changedLines;
  const areas = [...new Set(files.map((f) => (f.filename.includes('/') ? f.filename.split('/')[0] : '(root)')))];
  const t = p.thresholds;
  const split = changedLines > t.split_changed_lines;

  if (changedFilesTotal && changedFilesTotal > files.length) {
    add('too-big', `The PR changes ${fmt(changedFilesTotal)} files; GitHub only lists the first ${fmt(files.length)}.`);
  }
  if (split) {
    add(
      'split',
      `${fmt(changedLines)} changed lines is past the ${fmt(t.split_changed_lines)}-line split threshold. ` +
        'Please split it: big PRs get rubber-stamped or rejected.'
    );
  } else if (changedLines > t.deep_changed_lines) {
    add('size', `${fmt(changedLines)} changed lines (light review stops at ${fmt(t.deep_changed_lines)}).`);
  }
  if (ignoredLines > t.max_ignored_lines) {
    add(
      'generated-size',
      `${fmt(ignoredLines)} changed lines in generated or lock files (limit ${fmt(t.max_ignored_lines)}). ` +
        'Check they really are generated.'
    );
  }
  if (files.length > t.deep_files) {
    add('files', `${plural(files.length, 'file')} changed (light review stops at ${t.deep_files}).`);
  }
  if (areas.length > t.deep_top_level_areas) {
    add('spread', `Cross-cutting: touches ${areas.length} top-level folders (${areas.map(code).join(', ')}).`);
  }

  // 8. Contributors the team hasn't worked with yet.
  if (p.rules.first_time_contributors_are_deep && p.first_time_associations.includes(authorAssociation)) {
    add('first-time', 'First contribution from this author.');
  }

  return {
    tier: reasons.length ? 'deep' : 'light',
    reasons,
    owners: [...owners],
    split,
    labels: p.labels,
    stats: {
      changedLines,
      ignoredLines,
      files: files.length,
      countedFiles: counted.length,
      ignoredFiles: files.length - counted.length,
      areas,
    },
  };
}

// ---------------------------------------------------------------------------
// The merge gate. Pure function.
//   light: { sha, result } parsed from the light review comment, or null
//   approvals: number of people (not the author, not bots) whose latest
//              review approves the current head commit
// ---------------------------------------------------------------------------
export function decideGate({ tier, policy, headSha, light, approvals = 0 }) {
  const p = withDefaults(policy);
  if (tier === 'deep') {
    const need = p.deep_review.min_approvals;
    if (approvals >= need) {
      return { state: 'success', description: `Deep review: ${approvals} of ${need} approvals on the latest commit.` };
    }
    return {
      state: 'pending',
      description: `Deep review: ${approvals} of ${need} approvals on the latest commit.`,
    };
  }
  const onHead = light && light.sha && headSha && headSha.startsWith(light.sha);
  if (onHead && light.result === 'clean') {
    return { state: 'success', description: 'Light tier: the light review is clean on this commit.' };
  }
  if (onHead && light.result === 'failed') {
    return {
      state: 'pending',
      description: `Light tier: the light review didn't finish on ${short(headSha)}. Re-run it, or escalate.`,
    };
  }
  return { state: 'pending', description: `Light tier: waiting for a clean light review of ${short(headSha)}.` };
}

// Who may take the escalate label off a PR. Pure function.
export function canRemoveEscalation({ sender, prAuthor, role, policy }) {
  const p = withDefaults(policy);
  if (!sender || sender === prAuthor) return false;
  return p.escalation.removable_by.includes(role);
}

// Count approvals on the head commit from people other than the author.
export function countApprovals(reviews, { headSha, prAuthor }) {
  const latest = new Map();
  for (const r of reviews) {
    if (!r.user || r.user.type === 'Bot' || r.user.login === prAuthor) continue;
    if (!['APPROVED', 'CHANGES_REQUESTED', 'DISMISSED'].includes(r.state)) continue;
    latest.set(r.user.login, r); // the API lists reviews oldest first
  }
  return [...latest.values()].filter((r) => r.state === 'APPROVED' && r.commit_id === headSha).length;
}

export function parseLightComment(body) {
  const m = LIGHT_MARKER.exec(String(body || ''));
  return m ? { sha: m[1] || null, result: m[2] || null } : null;
}

// ---------------------------------------------------------------------------
// The sticky PR comment
// ---------------------------------------------------------------------------
export function renderComment(result, { approvalChecklistUrl, deepChecklistUrl, policyRef, gate, deepAiReview = false, notes = [] } = {}) {
  const { tier, reasons, owners, stats, labels } = result;
  const lines = [MARKER];

  if (tier === 'deep') {
    lines.push('### Review tier: Deep', '', 'This PR needs a deep review because:', '');
    for (const r of reasons) lines.push(`- ${r.text}`);
    lines.push(
      '',
      '**Next:** a deep review' +
        (owners.length ? ' with sign-off from the code owners' : '') +
        (deepChecklistUrl ? ` ([deep review checklist](${deepChecklistUrl}))` : '') +
        '. The AI reviews still run; they feed the deep review, they don\'t replace it.' +
        (deepAiReview ? ' Pass 3 also runs `threepass` on this PR and posts its report for the deep reviewers to start from.' : '')
    );
    if (owners.length) lines.push('', `**Owners:** ${owners.join(' ')}`);
  } else {
    lines.push(
      '### Review tier: Light',
      '',
      'No deep-review rules matched. Once the light review is clean on the latest commit and every Critical or ' +
        'Required comment is fixed or answered, one approver can merge after the light check' +
        (approvalChecklistUrl ? ` ([approval checklist](${approvalChecklistUrl}))` : '') +
        '.',
      '',
      `Anyone can raise this to deep by adding the ${code(labels.escalate)} label.`
    );
  }

  if (gate) lines.push('', `**Merge gate (${code(STATUS_CONTEXT)}):** ${gate.state === 'success' ? 'passing' : 'waiting'}. ${gate.description}`);
  for (const note of notes) lines.push('', `> ${note}`);

  const ignored = stats.ignoredFiles
    ? ` (plus ${fmt(stats.ignoredLines)} lines in ${plural(stats.ignoredFiles, 'generated or lock file')}, not counted)`
    : '';
  lines.push(
    '',
    `<sub>${fmt(stats.changedLines)} changed lines in ${plural(stats.countedFiles, 'file')} across ` +
      `${plural(stats.areas.length, 'top-level folder')}${ignored}. Rules: ${code('.github/review-policy.yml')}` +
      (policyRef ? ` on ${code(policyRef)}` : '') +
      '. Automation can raise a tier but never lowers one.</sub>'
  );
  return lines.join('\n') + '\n';
}

// ---------------------------------------------------------------------------
// GitHub API (only used when not in --dry-run)
// ---------------------------------------------------------------------------
function makeApi(token, baseUrl) {
  if (!token) throw new Error('GITHUB_TOKEN is not set');
  async function request(method, apiPath, body, { raw = false, allow404 = false } = {}) {
    const res = await fetch(baseUrl + apiPath, {
      method,
      headers: {
        Authorization: `Bearer ${token}`,
        Accept: raw ? 'application/vnd.github.raw+json' : 'application/vnd.github+json',
        'X-GitHub-Api-Version': '2022-11-28',
        'User-Agent': 'review-tier',
        ...(body ? { 'Content-Type': 'application/json' } : {}),
      },
      body: body ? JSON.stringify(body) : undefined,
    });
    if (res.status === 404 && (allow404 || method === 'DELETE')) return null;
    if (!res.ok) throw new Error(`${method} ${apiPath} -> ${res.status} ${await res.text()}`);
    if (res.status === 204) return null;
    return raw ? res.text() : res.json();
  }
  async function paginate(apiPath, maxPages = 30) {
    const out = [];
    for (let page = 1; page <= maxPages; page++) {
      const sep = apiPath.includes('?') ? '&' : '?';
      const batch = await request('GET', `${apiPath}${sep}per_page=100&page=${page}`);
      out.push(...batch);
      if (batch.length < 100) break;
    }
    return out;
  }
  return { request, paginate };
}

// The policy always comes from the PR's base branch, whichever event ran us.
async function loadPolicy(api, repo, baseRef) {
  if (process.env.POLICY_JSON) return JSON.parse(fs.readFileSync(process.env.POLICY_JSON, 'utf8'));
  const yaml = await api.request(
    'GET',
    `/repos/${repo}/contents/.github/review-policy.yml?ref=${encodeURIComponent(baseRef)}`,
    null,
    { raw: true, allow404: true }
  );
  if (yaml === null) throw new Error(`No .github/review-policy.yml on ${baseRef}`);
  const tmp = path.join(fs.mkdtempSync(path.join(os.tmpdir(), 'policy-')), 'review-policy.yml');
  fs.writeFileSync(tmp, yaml);
  // yq (mikefarah v4) is preinstalled on GitHub-hosted Ubuntu runners.
  return JSON.parse(execFileSync('yq', ['-o=json', '.', tmp], { encoding: 'utf8' }));
}

// Find the PR this run is about.
async function resolvePullRequest(api, repo, event) {
  if (event.pull_request) {
    // Refetch: the event payload can be stale by the time this runs.
    return api.request('GET', `/repos/${repo}/pulls/${event.pull_request.number}`);
  }
  const run = event.workflow_run;
  if (!run) return null;
  let number = run.pull_requests?.[0]?.number;
  if (!number && run.head_repository?.owner?.login && run.head_branch) {
    // Runs from forks don't list their PR; look it up by head branch.
    const head = `${run.head_repository.owner.login}:${run.head_branch}`;
    const open = await api.request('GET', `/repos/${repo}/pulls?state=open&head=${encodeURIComponent(head)}`);
    number = open?.[0]?.number;
  }
  return number ? api.request('GET', `/repos/${repo}/pulls/${number}`) : null;
}

async function setLabels(api, repo, number, current, result) {
  const { labels } = result;
  const want = [result.tier === 'deep' ? labels.deep : labels.light];
  if (result.split) want.push(labels.split);
  const remove = [result.tier === 'deep' ? labels.light : labels.deep];
  if (!result.split) remove.push(labels.split);

  const toAdd = want.filter((l) => !current.includes(l));
  if (toAdd.length) await api.request('POST', `/repos/${repo}/issues/${number}/labels`, { labels: toAdd });
  for (const l of remove.filter((l) => current.includes(l))) {
    await api.request('DELETE', `/repos/${repo}/issues/${number}/labels/${encodeURIComponent(l)}`);
  }
}

const isActionsBot = (c) => c.user?.type === 'Bot' && c.user?.login === 'github-actions[bot]';

// Pass 3 (deep review) runs `threepass` once per head commit of a deep,
// same-repo, non-draft PR. Its comment records the commit it reviewed.
export const threepassShaMarker = (sha) => `<!-- threepass-sha=${sha} -->`;
export function shouldDispatchDeepReview({ workflow, tier, isFork, isDraft, headSha, comments = [] }) {
  if (!workflow || tier !== 'deep' || isFork || isDraft || !headSha) return false;
  return !comments.some((c) => isActionsBot(c) && String(c.body || '').includes(threepassShaMarker(headSha)));
}

async function upsertComment(api, repo, number, comments, body) {
  const mine = comments.find((c) => isActionsBot(c) && c.body?.startsWith(MARKER));
  if (!mine) return api.request('POST', `/repos/${repo}/issues/${number}/comments`, { body });
  if (mine.body !== body) return api.request('PATCH', `/repos/${repo}/issues/comments/${mine.id}`, { body });
  return mine;
}

// ---------------------------------------------------------------------------
// CLI
// ---------------------------------------------------------------------------
function parseArgs(argv) {
  const args = {};
  for (let i = 0; i < argv.length; i++) {
    if (!argv[i].startsWith('--')) continue;
    const key = argv[i].slice(2);
    const next = argv[i + 1];
    if (next === undefined || next.startsWith('--')) args[key] = true;
    else args[key] = argv[++i];
  }
  return args;
}

async function dryRun(args) {
  const policy = JSON.parse(fs.readFileSync(args.policy, 'utf8'));
  const files = JSON.parse(fs.readFileSync(args.files, 'utf8'));
  const labels = args.labels ? String(args.labels).split(',').map((s) => s.trim()) : [];
  const result = decideTier({
    files,
    policy,
    labels,
    authorAssociation: args['author-association'] || 'MEMBER',
    changedFilesTotal: args['changed-files'] ? Number(args['changed-files']) : undefined,
    isFork: Boolean(args.fork),
  });
  const headSha = '0123456789abcdef0123456789abcdef01234567';
  const lightResult = args.light && args.light !== 'none' ? args.light : null;
  const gate = decideGate({
    tier: result.tier,
    policy,
    headSha,
    light: lightResult ? { sha: headSha, result: lightResult } : null,
    approvals: Number(args.approvals || 0),
  });
  if (args.json) {
    console.log(
      JSON.stringify({
        tier: result.tier,
        rules: result.reasons.map((r) => r.rule),
        split: result.split,
        owners: result.owners,
        gate,
        stats: result.stats,
      })
    );
  } else {
    console.log(renderComment(result, { policyRef: 'main', gate }));
  }
}

async function main() {
  const args = parseArgs(process.argv.slice(2));
  if (args['dry-run']) return dryRun(args);

  const event = JSON.parse(fs.readFileSync(process.env.GITHUB_EVENT_PATH, 'utf8'));
  const repo = process.env.GITHUB_REPOSITORY;
  const server = process.env.GITHUB_SERVER_URL || 'https://github.com';
  const api = makeApi(process.env.GITHUB_TOKEN, process.env.GITHUB_API_URL || 'https://api.github.com');

  const pr = await resolvePullRequest(api, repo, event);
  if (!pr) {
    console.log('No open pull request for this run; nothing to do.');
    return;
  }
  if (pr.state !== 'open') {
    console.log(`PR #${pr.number} is ${pr.state}; nothing to do.`);
    return;
  }

  const policy = await loadPolicy(api, repo, pr.base.ref);
  const p = withDefaults(policy);
  const notes = [];
  let current = (await api.paginate(`/repos/${repo}/issues/${pr.number}/labels`)).map((l) => l.name);

  // Only maintainers (and never the PR author) can take the escalate label off.
  if (event.action === 'unlabeled' && event.label?.name === p.labels.escalate && !current.includes(p.labels.escalate)) {
    const sender = event.sender?.login;
    let role = 'none';
    try {
      const perm = sender
        ? await api.request('GET', `/repos/${repo}/collaborators/${encodeURIComponent(sender)}/permission`, null, { allow404: true })
        : null;
      role = perm?.role_name || perm?.permission || 'none';
    } catch (err) {
      console.log(`Couldn't read ${sender}'s role (${err.message}); treating the removal as not allowed.`);
    }
    if (!canRemoveEscalation({ sender, prAuthor: pr.user?.login, role, policy })) {
      await api.request('POST', `/repos/${repo}/issues/${pr.number}/labels`, { labels: [p.labels.escalate] });
      current = [...current, p.labels.escalate];
      notes.push(
        `${code(p.labels.escalate)} was removed by ${code(sender || 'unknown')} and put back: only ` +
          `${p.escalation.removable_by.join(' or ')} roles can remove it, and never the PR author.`
      );
    }
  }

  const files = await api.paginate(`/repos/${repo}/pulls/${pr.number}/files`);
  const isFork = !pr.head.repo || pr.head.repo.full_name !== repo;
  const result = decideTier({
    files,
    policy,
    labels: current,
    authorAssociation: pr.author_association,
    changedFilesTotal: pr.changed_files,
    isFork,
  });

  // Gate inputs: the light review's verdict on this commit, and approvals of this commit.
  const comments = await api.paginate(`/repos/${repo}/issues/${pr.number}/comments`);
  const lightComment = comments.find((c) => isActionsBot(c) && parseLightComment(c.body));
  const light = lightComment ? parseLightComment(lightComment.body) : null;
  const reviews = await api.paginate(`/repos/${repo}/pulls/${pr.number}/reviews`);
  const approvals = countApprovals(reviews, { headSha: pr.head.sha, prAuthor: pr.user?.login });
  const gate = decideGate({ tier: result.tier, policy, headSha: pr.head.sha, light, approvals });

  const baseRef = pr.base.ref;
  const blob = (file) => `${server}/${repo}/blob/${encodeURIComponent(baseRef)}/${file}`;
  const checklist = blob(`.github/review/${result.tier === 'deep' ? 'deep-review' : 'approval'}-checklist.md`);
  const deepWorkflow = process.env.DEEP_REVIEW_WORKFLOW || '';
  const body = renderComment(result, {
    policyRef: baseRef,
    approvalChecklistUrl: blob('.github/review/approval-checklist.md'),
    deepChecklistUrl: blob('.github/review/deep-review-checklist.md'),
    gate,
    deepAiReview: Boolean(deepWorkflow) && !isFork,
    notes,
  });

  await setLabels(api, repo, pr.number, current, result);
  await upsertComment(api, repo, pr.number, comments, body);
  await api.request('POST', `/repos/${repo}/statuses/${pr.head.sha}`, {
    state: gate.state,
    context: STATUS_CONTEXT,
    description: gate.description.slice(0, 140),
    target_url: checklist,
  });

  // Workflow runs started by this job's token don't trigger other workflows,
  // except workflow_dispatch, so pass 3 is started explicitly. The deep
  // review re-checks the PR itself, so an extra dispatch only costs a no-op run.
  if (shouldDispatchDeepReview({ workflow: deepWorkflow, tier: result.tier, isFork, isDraft: pr.draft, headSha: pr.head.sha, comments })) {
    try {
      await api.request('POST', `/repos/${repo}/actions/workflows/${encodeURIComponent(deepWorkflow)}/dispatches`, {
        ref: pr.base.repo.default_branch,
        inputs: { pr: String(pr.number) },
      });
      console.log(`Started the deep review (pass 3) for ${pr.head.sha.slice(0, 7)}.`);
    } catch (err) {
      console.log(`Couldn't start the deep review (pass 3): ${err.message}`);
    }
  }

  if (process.env.GITHUB_STEP_SUMMARY) fs.appendFileSync(process.env.GITHUB_STEP_SUMMARY, body.replace(MARKER, ''));
  if (process.env.GITHUB_OUTPUT) fs.appendFileSync(process.env.GITHUB_OUTPUT, `tier=${result.tier}\ngate=${gate.state}\n`);
  console.log(
    `PR #${pr.number}: tier ${result.tier}` +
      (result.reasons.length ? ` (${result.reasons.map((r) => r.rule).join(', ')})` : '') +
      `; gate ${gate.state}: ${gate.description}`
  );
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  main().catch((err) => {
    console.error(err.message || err);
    process.exit(1);
  });
}
