# 9. Rollout

Don't switch everything on at once. Turn on the sensors first, watch them next to your current process, then let them change who reviews what.

## Stage 0: the basics (day 1)

- Add the [PR template](../templates/.github/pull_request_template.md) and [CODEOWNERS](../templates/.github/CODEOWNERS).
- Set up the branch ruleset: require a PR, 1 approval, review from Code Owners, and approval of the most recent push. See [setup](setup.md).

**Done when:** PRs come in with the template filled in, and owner approval is enforced on sensitive paths.

## Stage 1: Copilot on every PR (week 1)

- Turn on automatic Copilot review with **Review new pushes**.
- Add [`copilot-instructions.md`](../templates/.github/copilot-instructions.md) and the path-specific instructions.
- Keep reviewing exactly as you do today.

**Done when:** authors routinely fix or answer Copilot comments before asking for human review.

## Stage 2: agent review and tiers in shadow mode (weeks 2–3)

- Vendor the skill, add the agent review and tier check workflows, and create the labels.
- **Shadow mode:** the tier labels, agent summaries and `review-gate` status appear, but `review-gate` isn't required yet, and humans keep reviewing every PR the way they do today.
- After each human review, note on the PR:
  - Did the agent catch what you caught?
  - Did it flag anything you'd have missed?
  - Was the tier right?

**Done when** you've looked at the numbers from two weeks of PRs:

- Agent precision on Critical/Required findings is 70% or better.
- Tier labels match reviewers' judgment on 9 out of 10 PRs.
- Every rule that fires a lot has been tuned or justified.

## Stage 3: tiers go live (week 4)

- Add `review-gate` as a required status check in the ruleset.
- `tier/light`: one approver, the [light review checklist](../templates/.github/review/light-review-checklist.md), about 5 minutes.
- `tier/deep`: the code owner and a second reviewer, the [deep review checklist](../templates/.github/review/deep-review-checklist.md).
- Start the [trust ledger](08-earning-trust.md): tier mix, reverts and incidents by tier, sampled agent precision.
- Tell the team, out loud: anyone can add `escalate/deep`, any time, no explanation needed.

**Done when** you've had a month live:

- Median time to first human review on light PRs has dropped.
- No incident has traced back to a light-tier PR, or the ones that did have been fixed with policy changes.

## Stage 4: earn more (month 3 and on)

- Promote and demote areas based on the ledger, never on gut feel.
- Consider requiring conversation resolution before merge.
- Consider Copilot approvals (preview) only for promoted low-risk areas.
- Review the policy every quarter, together with CODEOWNERS.

## Who owns what

| Role | Owns |
|---|---|
| **Eng lead** | The policy, the ledger, monthly precision sampling, promotions and demotions |
| **Code owners** | Deep reviews in their area, and writing down the area's constraints |
| **Every reviewer** | Light reviews, and escalating when something feels off |
| **Authors** | The PR contract, small PRs, answering every Critical and Required comment |

## Small team version

For a team of a few people, or a solo maintainer:

- Run passes 1 and 2 on everything. Two different AI reviewers cost little next to the bugs they catch.
- Keep `sensitive_paths` short: auth, money, data deletion.
- For solo work, "deep review" can mean coming back to the PR the next day with the checklist. Solo developers can lean on lighter review if their tests are rigorous, and the deep review checklist's test questions are still the part that matters most.

Next: [FAQ](faq.md).
