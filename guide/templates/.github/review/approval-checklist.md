# Approval checklist (light tier)

For PRs labeled `tier/light`. Budget: about 5 minutes. You're not re-reading every line; the two AI reviews did the line-by-line pass. You're checking that the AI reviews are clean and that the change is what it says it is.

If you can't tick a box, add the `escalate/deep` label and say why in a comment. That's the whole escape hatch, and using it is never wrong.

## Before you start

- [ ] Both AI reviews have run on the latest push: Copilot's comments and the **Light review (pass 2)** summary.
- [ ] The `review-gate` check is green: the light review is clean on the latest commit.
- [ ] The light review summary has no "Could not verify" item that worries you.
- [ ] Every Critical or Required comment, from Copilot or the light review, is fixed or has a reply explaining why not.

## The 5-minute pass

- [ ] **Intent.** The PR description says what and why, and the light review's "What this PR does" matches it.
- [ ] **Proof.** There is real evidence it works: new or changed tests for changed behavior, or steps and screenshots for UI.
- [ ] **Shape.** The list of changed files makes sense for the stated intent. Nothing surprising: no new dependency, config change, deleted test or unrelated file.
- [ ] **Tests.** No assertion was loosened or rewritten to match new behavior. Nothing was skipped or deleted.
- [ ] **Understanding.** You could explain this change to a teammate in two sentences.

## Approve

Approve with a short comment, for example:

> Light review: AI reviews clean, intent matches, tests cover the change.

Approving means you vouch for it. "The AI said it was fine" is not a reason to approve. It's a reason you only needed 5 minutes.
