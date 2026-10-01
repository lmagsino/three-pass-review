# Deep review checklist

For PRs labeled `tier/deep`. This is where human review time goes: verification, constraints and recoverability. Budget: 30 to 60 minutes. If it would take longer, the PR is too big. Ask for a split rather than skimming.

Who signs off: a code owner for the area (GitHub enforces this through CODEOWNERS), plus a second reviewer. The `review-gate` check passes once two people other than the author have approved the latest commit. For changes that can't be undone, make sure the second reviewer knows the area too.

## 1. Intent (5 min)

- [ ] I can state what the PR changes and why, in my own words.
- [ ] The PR description covers proof it works, risk, rollback and AI involvement. If not, ask before going further.
- [ ] I've read the tier comment (why it's deep) and the agent summary, including **Worth opening** and **Could not verify**.

## 2. Verify the verification (10–15 min)

Read the test changes more carefully than the code.

- [ ] The tests would fail without this change. (Check out the branch and revert the fix if you're not sure.)
- [ ] No assertion was rewritten to match new behavior. Nothing was skipped, deleted or loosened.
- [ ] Edge cases and error paths for the changed behavior are covered, not only the happy path.
- [ ] For anything visible or operational, I've seen it work: preview, screenshot, log, or I ran it.

## 3. Constraints and blast radius (10–15 min)

- [ ] The change keeps the rules this area depends on (for example: only checkout code calls `charge()`, every handler checks permissions, money is never a float). If those rules aren't written down, write them down after this review.
- [ ] Every caller of a changed contract (function signature, API response, event, schema, config key) still works. The agent's blast-radius table is a starting point, not the answer.
- [ ] No feature logic leaked into shared modules. No new dependency the area didn't need.
- [ ] Security: input validated at the boundary, authorization checked, nothing sensitive logged.

## 4. Recoverability (5–10 min)

- [ ] If this breaks in production, we can undo it: plain revert, feature flag, or a tested down-migration.
- [ ] Migrations are backwards compatible with the code currently running (expand first, contract later).
- [ ] Anything that can't be undone (deleted or rewritten data, emails, payments, webhooks, removed public API) is called out, has a second reviewer, and has a plan.
- [ ] We'll know if it breaks: logs, metrics or alerts cover the new path.

## 5. Comprehension gate

- [ ] I understand this code well enough to debug it at 2am. If an agent wrote it, someone on the team now does too.

## Sign off

Approve with a comment in this shape, so the decision is on record:

```
Deep review
- Verified: <what you checked and how>
- Constraints: <rules you confirmed, or "none specific">
- Rollback: <how we undo it>
- Follow-ups: <issues filed, or "none">
```

If a finding from the AI reviews was wrong, say so in a reply. That feedback is how the team learns where the agents can be trusted.
