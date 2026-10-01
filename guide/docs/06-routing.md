# 6. Routing: light or deep

Every PR gets one tier. The rules are deterministic, live in [`.github/review-policy.yml`](../templates/.github/review-policy.yml), and are applied by [`review-tier.mjs`](../templates/.github/scripts/review-tier.mjs).

Three rules hold the system together:

1. **The rules set the floor.** If any rule matches, the PR is deep.
2. **Escalation only goes up.** The light review or any person can add `escalate/deep`. Nothing automated lowers a tier, and only a maintainer (never the PR author) can take the label off.
3. **The rules come from the base branch.** The policy is read from the PR's base branch, so a PR can't edit it to make its own review lighter.

## The rules

| Rule | Default | Why |
|---|---|---|
| Escalated | `escalate/deep` label present | The light review or a person asked for deep. Sticky |
| No light review | `skip-light-review` label present | The light tier needs a clean light review |
| Fork | PR comes from a fork | The light review doesn't run on forks, so the light tier can't be cleared |
| Review setup | Any change to `.github/workflows/**`, `.github/review-policy.yml`, `.github/scripts/**`, `.github/review/**`, Copilot instructions, skills and agents (`.github/skills/**`, `.github/agents/**`, `.agents/**`), `CODEOWNERS`, `.claude/**`, `CLAUDE.md`, `AGENTS.md`, `REVIEW.md`, `GEMINI.md` | A PR shouldn't quietly change its own reviewers. Built into the script; the policy can't turn it off |
| Sensitive paths | `sensitive_paths` in the policy (auth, payments, migrations, infra in the template) | Core paths need an owner. Renamed files are checked under their old path too |
| Deleted tests | A removed test file, or a test renamed to a non-test path | Deleting tests is how bad changes go green |
| Quality gates | Lint, type-check, test or coverage config changed | Thresholds can be lowered to get green |
| Deleted source | A removed non-test, non-generated file, or source moved into a generated path | Something may still call it |
| Dependencies | `package.json`, `go.mod`, `pyproject.toml` and similar | Supply chain, and a wide blast radius |
| Size | More than 400 changed lines | Past what a light review can vouch for |
| Split | More than 1,000 changed lines | Also adds `needs-split`: please break it up |
| Generated size | More than 5,000 lines in "generated" or lock files | Hand-written code hidden in a generated folder |
| Files | More than 30 files | Same as size |
| Spread | More than 3 top-level folders | Cross-cutting changes have a wide blast radius |
| First-time contributor | `author_association` is first-time or none | No trust history yet |
| Too big to list | GitHub's file list was truncated | Can't check what you can't see |

Lines in lockfiles, snapshots, minified and generated files don't count toward size, but those files still count toward the file and folder limits. If no rule matches, the PR is light.

### Why these proxies

Blast radius is really about *who depends on what changed*. A file-level policy can't see a call graph, so it uses proxies that are cheap and can't be argued with: paths, size, spread, deletions, dependencies. The light review fills the gap. It searches for actual callers and escalates when a change reaches further than the paths suggest.

If you adopt a tool that builds a real call graph of a PR, add its output as one more escalation signal. Don't replace the floor rules with it.

## The merge gate

The tier check also publishes the `review-gate` commit status on the PR's latest commit:

- **Light** passes once the light review is clean on that commit. Its comment records the commit it reviewed and its verdict, and the gate only trusts comments posted by `github-actions[bot]`.
- **Deep** passes once `deep_review.min_approvals` people (default 2; not the author, not bots) have approved that commit.

It re-checks when the PR changes, when the light review finishes, and when someone submits or dismisses a review (through `review-submitted.yml`). Add `review-gate` as a required status check once you go live ([rollout](09-rollout.md)).

## The tier comment

The tier check keeps one comment on the PR, updated in place:

```markdown
### Review tier: Deep

This PR needs a deep review because:

- Touches `src/payments/**` (money movement): `src/payments/refund.ts`, `src/payments/refund.test.ts`.
- Deletes source files (does anything still call them?): `src/legacy/old-refund.ts`.
- 424 changed lines (light review stops at 400).

**Next:** a deep review with sign-off from the code owners (deep review checklist). The AI reviews
still run; they feed the deep review, they don't replace it. Pass 3 also posts a reviewer brief (the
change at a high level, risks, where to look first, findings and a sign-off draft) for the deep
reviewers to start from.

**Owners:** @your-org/payments

**Merge gate (`review-gate`):** waiting. Deep review: 1 of 2 approvals on the latest commit.
```

## Keep the policy and CODEOWNERS in sync

The two files do different jobs:

- **`review-policy.yml`** decides the **tier**: labels, the comment, the gate, which checklist applies.
- **`CODEOWNERS`** decides **who must approve**. GitHub enforces it when the ruleset has "Require review from Code Owners" turned on.

Every `sensitive_paths` entry should have a matching CODEOWNERS line. If they drift, you get a PR labeled deep with no owner required, or an owner required on a PR labeled light. Review both together whenever either changes.

## When the tier is wrong

**It said light, but it should be deep.** Add `escalate/deep`. Anyone can, at any time. Then add the path or pattern to the policy so it's caught next time.

**It said deep, and it shouldn't have.**
- If a **rule** matched (path, size and so on): do the deep review anyway, then raise a PR to tune the policy. That PR touches the policy, so it gets a deep review too.
- If the **light review escalated** and was wrong: a maintainer (admin or maintain role, set by `escalation.removable_by`) removes `escalate/deep` and leaves a comment saying why. If anyone else removes it, the PR author included, the tier check puts it back and says so. Count it as a false escalation in the [trust ledger](08-earning-trust.md). Frequent false escalations mean the prompt needs work.

## Why `pull_request_target` is safe here

The tier check needs to label PRs and set statuses on PRs from forks too. That needs a write token, which `pull_request` doesn't give fork PRs. `pull_request_target` does, and it's known to be dangerous **when a workflow checks out and runs PR code**. This one doesn't:

- It checks out one file, the tier script, from the trusted branch.
- It reads the PR, its files, comments and reviews through the API, and the policy from the PR's base branch.
- It never installs, builds or runs anything from the PR.
- File names from the PR are escaped before they go into the comment.

Keep it that way. Never add a checkout of the PR head to `review-tier.yml`.

## What the gate does and doesn't protect against

The gate, the label guard and the policy-from-base design stop **accidents and shortcuts**: an approval that came before the light review escalated, an author removing an escalation, a PR that edits the rules or the reviewer instructions, an over-hasty light approval on a PR the light review never cleared.

They don't stop **someone with write access who sets out to bypass them**. Anyone who can run workflows can post a commit status. The GitHub-native controls (CODEOWNERS, required approvals, approval of the most recent push) are your hard guarantees. Everything else makes the right path the easy path.

## Tuning

Start with the defaults, run in shadow mode for two weeks ([rollout](09-rollout.md)), then adjust:

- **Too many PRs land in deep** (say over 40%)? Check which rules fire most often in the tier comments. Common fixes: add generated paths to `ignore_for_size`, or turn off `dependency_changes_are_deep` for internal packages.
- **Too few land in deep**, or incidents come from light PRs? Add sensitive paths, and lower `deep_changed_lines`.
- **Open source with many fork PRs?** They're all deep, because pass 2 can't run on them and the light tier depends on a clean light review. That's deliberate. To lighten the load, give trusted regular contributors push access to branches in the main repo, so their PRs get the light review and, when deep, the reviewer brief.
- **Moving a path from deep to light** is a trust decision, not a tuning tweak. Use [earning trust](08-earning-trust.md).

Next: [for authors](07-for-authors.md).
