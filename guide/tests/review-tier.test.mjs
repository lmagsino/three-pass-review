// Run with: node --test   (from the repo root)
// Converts the template policy with yq (mikefarah) if available, otherwise
// with python3 + PyYAML.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import {
  globToRegExp,
  matchAny,
  decideTier,
  decideGate,
  canRemoveEscalation,
  countApprovals,
  parseLightComment,
  renderComment,
  code,
  MARKER,
} from '../templates/.github/scripts/review-tier.mjs';

const root = path.dirname(path.dirname(fileURLToPath(import.meta.url)));
const policyYaml = path.join(root, 'templates/.github/review-policy.yml');

function loadPolicy() {
  try {
    return JSON.parse(execFileSync('yq', ['-o=json', '.', policyYaml], { encoding: 'utf8' }));
  } catch {
    return JSON.parse(
      execFileSync('python3', ['-c', 'import json,sys,yaml; print(json.dumps(yaml.safe_load(open(sys.argv[1]))))', policyYaml], {
        encoding: 'utf8',
      })
    );
  }
}
const policy = loadPolicy();

const f = (filename, additions = 10, deletions = 0, extra = {}) => ({
  filename,
  status: 'modified',
  additions,
  deletions,
  ...extra,
});
const decide = (files, opts = {}) => decideTier({ files, policy, authorAssociation: 'MEMBER', ...opts });
const rules = (r) => r.reasons.map((x) => x.rule);

test('globs behave like CODEOWNERS / gitignore', () => {
  assert.ok(matchAny('src/auth/login.ts', ['src/auth/**']));
  assert.ok(matchAny('src/auth/deep/nested/x.ts', ['src/auth/**']));
  assert.ok(!matchAny('src/authors/list.ts', ['src/auth/**']));
  assert.ok(!matchAny('lib/src/auth/x.ts', ['src/auth/**']), 'patterns with a slash are anchored to the root');
  assert.ok(matchAny('package-lock.json', ['package-lock.json']));
  assert.ok(matchAny('apps/web/package-lock.json', ['package-lock.json']), 'no slash = any depth');
  assert.ok(matchAny('CODEOWNERS', ['CODEOWNERS']));
  assert.ok(matchAny('docs/CODEOWNERS', ['CODEOWNERS']));
  assert.ok(matchAny('a/b/c.test.ts', ['*.test.*']));
  assert.ok(matchAny('x/__generated__/y/z.ts', ['**/__generated__/**']));
  assert.ok(matchAny('docs/guide/a.md', ['docs/**/*.md']));
  assert.ok(matchAny('docs/a.md', ['docs/**/*.md']), "'**/' also matches zero folders");
  assert.ok(matchAny('src/x.ts', ['/src/']), 'leading slash anchors, trailing slash means everything under');
  assert.ok(matchAny('src.ts', ['src?ts']), '? matches one character');
  assert.ok(!matchAny('src/ts', ['src?ts']), '? does not match a slash');
  assert.equal(globToRegExp('a.b').test('aXb'), false, 'dots are literal');
});

test('small change in ordinary code is light', () => {
  const r = decide([f('src/ui/button.tsx', 40, 5), f('src/ui/button.test.tsx', 20)]);
  assert.equal(r.tier, 'light');
  assert.deepEqual(r.reasons, []);
  assert.equal(r.stats.changedLines, 65);
});

test('sensitive path is deep and names the owners', () => {
  const r = decide([f('src/payments/refund.ts', 12, 3)]);
  assert.equal(r.tier, 'deep');
  assert.deepEqual(rules(r), ['sensitive-path']);
  assert.deepEqual(r.owners, ['@your-org/payments']);
});

test('moving a file OUT of a sensitive folder is still deep', () => {
  const r = decide([f('src/utils/charge.ts', 0, 0, { status: 'renamed', previous_filename: 'src/payments/charge.ts' })]);
  assert.equal(r.tier, 'deep');
  assert.ok(rules(r).includes('sensitive-path'));
});

test('changes to the review setup are always deep', () => {
  for (const file of [
    '.github/workflows/ci.yml',
    '.github/review-policy.yml',
    '.claude/review/light-review.md',
    '.claude/review/methods/pr-review-toolkit.md',
    '.claude/review/skills/code-review-and-quality/SKILL.md',
    '.claude/skills/anything/SKILL.md',
    '.agents/skills/x/SKILL.md',
    '.github/skills/code-review/SKILL.md',
    '.github/copilot-instructions.md',
    'CODEOWNERS',
    '.github/CODEOWNERS',
    'packages/api/CLAUDE.md',
  ]) {
    const r = decide([f(file, 1)]);
    assert.equal(r.tier, 'deep', file);
    assert.ok(rules(r).includes('review-machinery'), file);
  }
});

test('escalate label is sticky', () => {
  const r = decide([f('src/ui/button.tsx', 2)], { labels: ['escalate/deep', 'bug'] });
  assert.equal(r.tier, 'deep');
  assert.deepEqual(rules(r), ['escalated']);
  const plain = decide([f('src/ui/button.tsx', 2)], { labels: ['tier/deep'] });
  assert.equal(plain.tier, 'light', 'a stale tier/deep label alone does not keep a PR deep');
});

test('size thresholds: light up to 400, deep above, split above 1000', () => {
  assert.equal(decide([f('src/a.ts', 300, 100)]).tier, 'light');
  const deep = decide([f('src/a.ts', 300, 101)]);
  assert.deepEqual(rules(deep), ['size']);
  assert.equal(deep.split, false);
  const huge = decide([f('src/a.ts', 900, 200)]);
  assert.deepEqual(rules(huge), ['split']);
  assert.equal(huge.split, true);
});

test('lockfiles and generated files do not count toward size', () => {
  const r = decide([f('src/a.ts', 50), f('package-lock.json', 1500, 1000), f('src/__generated__/schema.ts', 2000)]);
  assert.equal(r.tier, 'light');
  assert.equal(r.stats.changedLines, 50);
  assert.equal(r.stats.ignoredFiles, 2);
  const tooMuch = decide([f('src/generated/handwritten.ts', 6000)]);
  assert.deepEqual(rules(tooMuch), ['generated-size'], 'a huge "generated" change is suspicious');
});

test('dependency and quality-gate changes are deep', () => {
  assert.deepEqual(rules(decide([f('apps/web/package.json', 1, 1)])), ['dependencies']);
  assert.deepEqual(rules(decide([f('vitest.config.ts', 1, 1)])), ['quality-gate']);
  assert.deepEqual(rules(decide([f('tsconfig.json', 1, 1)])), ['quality-gate']);
});

test('deleting tests or source files is deep; adding tests is not', () => {
  assert.deepEqual(rules(decide([f('src/a.test.ts', 0, 80, { status: 'removed' })])), ['deleted-tests']);
  assert.deepEqual(rules(decide([f('src/legacy.ts', 0, 80, { status: 'removed' })])), ['deleted-source']);
  assert.equal(decide([f('src/new.test.ts', 80, 0, { status: 'added' })]).tier, 'light');
  assert.equal(decide([f('snapshots/x.snap', 0, 80, { status: 'removed' })]).tier, 'light', 'ignored files are not "source"');
  const renamedTest = decide([f('attic/x.ts.txt', 0, 0, { status: 'renamed', previous_filename: 'src/x.test.ts' })]);
  assert.ok(rules(renamedTest).includes('deleted-tests'), 'renaming a test away counts as deleting it');
  const intoGenerated = decide([f('src/generated/charge.ts', 0, 0, { status: 'renamed', previous_filename: 'src/charge.ts' })]);
  assert.ok(rules(intoGenerated).includes('deleted-source'), 'moving source into an ignored path counts as deleting it');
});

test('cross-cutting and many-file PRs are deep', () => {
  const spread = decide([f('api/a.ts', 5), f('web/b.ts', 5), f('worker/c.ts', 5), f('shared/d.ts', 5)]);
  assert.deepEqual(rules(spread), ['spread']);
  const many = decide(Array.from({ length: 31 }, (_, i) => f(`src/f${i}.ts`, 1)));
  assert.deepEqual(rules(many), ['files']);
});

test('first-time contributors are deep', () => {
  const r = decide([f('src/ui/button.tsx', 2)], { authorAssociation: 'FIRST_TIME_CONTRIBUTOR' });
  assert.deepEqual(rules(r), ['first-time']);
});

test('forks and skipped light reviews are deep', () => {
  assert.deepEqual(rules(decide([f('src/ui/a.ts', 2)], { isFork: true })), ['fork']);
  assert.deepEqual(rules(decide([f('src/ui/a.ts', 2)], { labels: ['skip-light-review'] })), ['no-light-review']);
});

test('gate: light needs a clean light review on the head commit', () => {
  const head = 'abcdef1234567890abcdef1234567890abcdef12';
  assert.equal(decideGate({ tier: 'light', policy, headSha: head, light: null }).state, 'pending');
  assert.equal(decideGate({ tier: 'light', policy, headSha: head, light: { sha: head, result: 'clean' } }).state, 'success');
  assert.equal(decideGate({ tier: 'light', policy, headSha: head, light: { sha: 'ffffff1', result: 'clean' } }).state, 'pending', 'stale review');
  assert.equal(decideGate({ tier: 'light', policy, headSha: head, light: { sha: head, result: 'failed' } }).state, 'pending');
});

test('gate: deep needs enough approvals of the head commit', () => {
  assert.equal(decideGate({ tier: 'deep', policy, headSha: 'a', approvals: 1 }).state, 'pending');
  assert.equal(decideGate({ tier: 'deep', policy, headSha: 'a', approvals: 2 }).state, 'success');
  const reviews = [
    { user: { login: 'ana', type: 'User' }, state: 'APPROVED', commit_id: 'old' },
    { user: { login: 'ana', type: 'User' }, state: 'APPROVED', commit_id: 'head' },
    { user: { login: 'ben', type: 'User' }, state: 'APPROVED', commit_id: 'head' },
    { user: { login: 'ben', type: 'User' }, state: 'COMMENTED', commit_id: 'head' },
    { user: { login: 'cy', type: 'User' }, state: 'APPROVED', commit_id: 'old' },
    { user: { login: 'dee', type: 'User' }, state: 'APPROVED', commit_id: 'head' },
    { user: { login: 'dee', type: 'User' }, state: 'DISMISSED', commit_id: 'head' },
    { user: { login: 'Copilot', type: 'Bot' }, state: 'APPROVED', commit_id: 'head' },
    { user: { login: 'author', type: 'User' }, state: 'APPROVED', commit_id: 'head' },
  ];
  assert.equal(countApprovals(reviews, { headSha: 'head', prAuthor: 'author' }), 2, 'ana and ben only');
});

test('only maintainers, never the author, can remove an escalation', () => {
  assert.equal(canRemoveEscalation({ sender: 'author', prAuthor: 'author', role: 'admin', policy }), false);
  assert.equal(canRemoveEscalation({ sender: 'lead', prAuthor: 'author', role: 'maintain', policy }), true);
  assert.equal(canRemoveEscalation({ sender: 'dev', prAuthor: 'author', role: 'write', policy }), false);
});

test('light review comment marker and file-name escaping', () => {
  assert.deepEqual(parseLightComment('<!-- light-review sha=abc1234 result=clean -->\n### ...'), { sha: 'abc1234', result: 'clean' });
  assert.equal(parseLightComment('hello'), null);
  assert.equal(code('a`b\n@team'), '`a?b?@team`');
});

test('more files than the API lists is deep', () => {
  const r = decide([f('src/a.ts', 1)], { changedFilesTotal: 3500 });
  assert.ok(rules(r).includes('too-big'));
});

test('rules can be switched off in the policy', () => {
  const relaxed = { ...policy, rules: { ...policy.rules, dependency_changes_are_deep: false } };
  assert.equal(decideTier({ files: [f('package.json', 1, 1)], policy: relaxed }).tier, 'light');
});

test('comment starts with the marker and explains the tier', () => {
  const deep = renderComment(decide([f('src/payments/a.ts', 3)]), {
    deepChecklistUrl: 'https://example.com/deep',
    policyRef: 'main',
  });
  assert.ok(deep.startsWith(MARKER));
  assert.match(deep, /Review tier: Deep/);
  assert.match(deep, /@your-org\/payments/);
  assert.match(deep, /deep review checklist\]\(https:\/\/example.com\/deep\)/);
  const light = renderComment(decide([f('src/ui/a.ts', 3)]), { approvalChecklistUrl: 'https://example.com/light' });
  assert.match(light, /Review tier: Light/);
  assert.match(light, /`escalate\/deep`/);
});
