# 5. Pass 3: deep review

**Job:** a code owner decides whether a high-blast-radius change is safe to ship, and makes sure someone on the team understands it.

This is where human review time goes: verification, constraints and recoverability, on the changes where a mistake would really hurt.

## When a PR gets a deep review

A PR is `tier/deep` when any of these is true (details in [routing](06-routing.md)):

- It touches a **core or sensitive path** in the policy: auth, payments, migrations, infrastructure, whatever yours are.
- It changes the **review setup itself**: workflows, policy, CODEOWNERS, reviewer instructions.
- It **deletes tests**, or changes **lint, test or coverage config**.
- It **deletes source files** or changes **dependencies**.
- It's **big or cross-cutting**: over 400 changed lines, over 30 files, or more than 3 top-level folders.
- It's from a **first-time contributor**.
- The **agent escalated it**, or **someone added `escalate/deep`**.

## Who reviews

- **The code owner** for the area. GitHub enforces this through `CODEOWNERS` and the "Require review from Code Owners" rule.
- **A second reviewer.** The `review-gate` status passes only when 2 people (not the author) have approved the latest commit; set the number with `deep_review.min_approvals`. Paths without a code owner (deep because of size or an escalation, say) are covered by this rule.
- **An extra reviewer** for anything that can't be undone: destructive migrations, data deletion, payments, removing public API.
- **A rotation for growth.** Have less experienced engineers shadow deep reviews. Review is still how knowledge spreads on a team, and the light tier means fewer chances for that to happen by accident.

## How to do it

Use the [deep review checklist](../templates/.github/review/deep-review-checklist.md). Budget 30 to 60 minutes. If it'll take longer, the PR is too big: ask for a split rather than skimming.

### 1. Intent (5 minutes)

Before reading code, read:

- the PR description,
- the tier comment (why this is deep),
- the agent summary: **What this PR does**, **Blast radius**, **Worth opening** and **Could not verify**.

If you can't state what the PR does and why, stop and ask the author.

### 2. Verify the verification (10–15 minutes)

This matters more than reading the implementation. Read the test changes more carefully than the code.

- Would the tests fail without the change? If you're not sure, check out the branch, revert the fix and run them.
- Were assertions rewritten to match the new behavior? Were tests skipped, deleted or loosened?
- Are error paths and edge cases covered, not only the happy path?
- For anything visible or operational, see it work: a preview, a screenshot, a log, or run it yourself.

### 3. Constraints and blast radius (10–15 minutes)

- **Invariants.** Check the rules this area depends on, for example "only checkout code calls `charge()`", "every handler checks permissions", "money is never a float". If those rules live only in people's heads, write them down after this review; Addy's [`constraint-driven-development`](https://github.com/addyosmani/agent-skills/tree/main/skills/constraint-driven-development) skill is a good way to do it.
- **Callers.** Every caller of a changed contract still works. The agent's blast-radius table is where you start, not where you stop.
- **Boundaries.** No feature logic leaked into shared modules, and no dependency the area doesn't need.
- **Security.** Input validated at the boundary, authorization checked, nothing sensitive logged.

### 4. Recoverability (5–10 minutes)

- Can we undo this in production? Plain revert, feature flag, or a tested down-migration.
- Are migrations compatible with the code that's running right now? Expand first, contract later.
- Is anything permanent: deleted data, sent emails, charged cards, fired webhooks, removed public API? Then it needs a second reviewer and a plan.
- Will we know if it breaks? Logs, metrics or alerts on the new path.

### 5. The comprehension gate

Approve only if you understand the change well enough to debug it at 2am. If an agent wrote it, someone on the team has to own it now. That person might be you.

### 6. Sign off

Approve with a short, structured note so the decision is on record:

```
Deep review
- Verified: ran the refund tests with the fix reverted; 2 fail as expected
- Constraints: refunds still idempotent on retry_key; amounts stay in minor units
- Rollback: plain revert; no migration
- Follow-ups: #1234 (add alert on refund failures)
```

Where an AI finding was wrong, reply on it and say so. Those replies feed the [trust ledger](08-earning-trust.md).

## Anti-patterns

- **"Both AIs were clean, LGTM."** A clean AI review on a deep-tier PR tells you where not to look first. It doesn't tell you the change is safe.
- **Re-reading every line.** Spend the time on tests, contracts and rollback, not on things the AI passes and linters cover.
- **Reviewing a 2,000-line PR.** Ask for a split. Big PRs get rubber-stamped or rejected, and both are failures.
- **Accepting "I'll clean it up later".** Later rarely comes. Ask for the fix now, or a filed issue with an owner.
- **Silent approval.** No sign-off note means nobody can tell later what was checked.

Next: [routing](06-routing.md).
