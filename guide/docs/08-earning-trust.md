# 8. Earning trust

Deep review is also where you earn trust in what the agents can safely cover. Trust here isn't a feeling. It's a record: which areas the agents reviewed alone, how often that went wrong, and whether their findings were real.

Keep the record, move areas between tiers based on it, and move them back fast when it says to.

## The trust ledger

Track five numbers, monthly, per area (top-level folder or sensitive path):

| Signal | How to get it | What it tells you |
|---|---|---|
| **Tier mix** | Count merged PRs labeled `tier/light` vs `tier/deep` | Is human attention going where you think? |
| **Escaped defects by tier** | Reverts and incident-linked PRs, by the original PR's tier | Is light review letting real problems through? |
| **AI precision** | Sample 20 Critical/Required agent findings a month and mark each real or false | Can you believe the agent when it flags something? |
| **False escalations** | Count of `escalate/deep` labels a maintainer removed (only maintainers can) | Is the agent crying wolf? |
| **Review time** | Time to first human review and to merge, by tier | Is the system actually saving time? |

### Pulling the numbers with `gh`

```bash
SINCE=2026-09-01

# Tier mix
gh pr list --state merged --label tier/light --search "merged:>=$SINCE" --limit 1000 --json number --jq length
gh pr list --state merged --label tier/deep  --search "merged:>=$SINCE" --limit 1000 --json number --jq length

# PRs that were reverted (GitHub's revert button writes "Reverts owner/repo#123")
gh pr list --state merged --search "Revert in:title merged:>=$SINCE" --limit 200 --json body \
  --jq '.[] | (.body // "" | capture("Reverts [^#\\s]+#(?<n>[0-9]+)").n) // empty' \
| while read -r n; do
    echo "#$n $(gh pr view "$n" --json labels --jq '[.labels[].name | select(startswith("tier/"))] | join(",")')"
  done
```

For incidents, put the PR number in every postmortem, so incidents can be traced back to a PR and its tier the same way.

For AI precision, a person looks at the sample. There's no shortcut. People move from reading every line to sampling and auditing what the agents do. Twenty findings take about half an hour, and that half hour is what lets you trust the agent on everything else.

## Promoting an area from deep to light

An area can move out of `sensitive_paths` (and out of `CODEOWNERS`) when all of these hold:

- **8+ weeks** of deep reviews in that area with no escaped defects.
- **Agent precision of 80% or more** on sampled findings in that area.
- **Tests that would catch a regression**: real coverage of the behavior, not just a line-coverage number.
- **Everything reversible**: changes there can be undone with a plain revert or a flag.
- **The owner agrees** and says so in the policy PR.

Promotion is a PR to `review-policy.yml` and `CODEOWNERS`, which itself gets a deep review. Write the evidence in the PR description.

These numbers are starting points, not standards. Pick your own, write them down, and apply them the same way every time.

## Demoting an area back to deep

Do it immediately, and argue about it later:

- **Any incident or revert** traced to a light-tier PR puts that area back in `sensitive_paths` the same day.
- **Agent precision below 60%**, or a run of false escalations, means the agent's output in that area can't be trusted. Fix the prompt, or treat the area as deep until you do.

Then run a short retro. Which pass should have caught it? Copilot, the agent, the tier rules, or the human? Fix that pass.

## Keeping recoverability

Trust is cheaper when mistakes are cheap to undo. These habits make more of your codebase safe for light review:

- **Feature flags** for behavior changes, so "undo" means flipping a flag, not a deploy.
- **Expand and contract migrations**: add the new thing, move readers and writers over, then remove the old thing, each in its own PR.
- **Small PRs**, so a revert removes one change, not twelve.
- **Alerts on new paths**, so you find out from a dashboard and not from a customer.

Anything a plain revert can't undo stays in deep review, however long the area's record is.

## Later steps (optional)

Once you have a few months of data:

- **Require conversation resolution before merging** (a ruleset option), so no AI comment gets ignored silently. This works best once AI comments are mostly signal.
- **Copilot approvals for promoted low-risk areas.** GitHub has a public preview in which Copilot can submit an approval that counts toward required approvals, and admins can limit which file paths that applies to. It's off by default. If you try it, limit it to areas with a long clean record and nothing irreversible, like docs and internal tooling. Approval stays a human call on anything that matters.

Next: [rollout](09-rollout.md).
