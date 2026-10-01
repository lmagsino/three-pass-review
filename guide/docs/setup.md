# Setup

About 30 minutes for one repository. You need admin access to the repo, the GitHub CLI (`gh`), and an Anthropic API key (or one of the cloud providers `claude-code-action` supports).

## 1. Copy the kit into your repo

```bash
git clone https://github.com/lmagsino/three-pass-review.git
cd your-repo && git switch -c three-pass-review
bash ../three-pass-review/guide/scripts/install.sh . --light-reviewer addy   # or pr-review-toolkit
```

`install.sh` does four things:

- **Copies everything in [`templates/`](../templates).** It never overwrites a file you already have, including a CODEOWNERS or PR template in another of GitHub's locations, and it lists what it skipped so you can merge by hand.
- **Vendors Addy Osmani's `code-review-and-quality` skill** at a pinned commit.
- **Sets the pass 2 reviewer** you picked.
- **Pins pass 3's `threepass`** to the exact commit of the kit you ran it from.

**Using it across projects.** Run the same command in each repository. When the kit improves, pull it and rerun with `--upgrade` in each project:

```bash
git -C ../three-pass-review pull
bash ../three-pass-review/guide/scripts/install.sh . --upgrade
```

`--upgrade` refreshes the kit's own files (workflows, scripts, reviewer instructions, checklists) and moves the `threepass` pin. It never touches the files your team edits: `review-policy.yml`, `CODEOWNERS`, the PR template, the Copilot instructions. It touches the review setup, so the upgrade PR gets a deep review.

You end up with:

```
.github/
  CODEOWNERS
  copilot-instructions.md
  instructions/sensitive-paths.instructions.md
  pull_request_template.md
  review-policy.yml
  review/approval-checklist.md
  review/deep-review-checklist.md
  scripts/review-tier.mjs
  scripts/post-light-review.sh
  scripts/post-deep-review.sh
  workflows/review-tier.yml
  workflows/review-submitted.yml
  workflows/light-review.yml                       (pass 2)
  workflows/deep-review.yml                        (pass 3: the reviewer brief)
.claude/
  review/light-review.md
  review/methods/addy.md
  review/methods/pr-review-toolkit.md
  review/skills/code-review-and-quality/SKILL.md   (Addy Osmani, MIT, pinned)
  review/references/security-checklist.md          (Addy Osmani, MIT, pinned)
  review/references/performance-checklist.md       (Addy Osmani, MIT, pinned)
  review/THIRD_PARTY_NOTICES.md
```

The skill sits in `.claude/review/skills/`, not `.claude/skills/`, on purpose. Copilot and Claude Code auto-load skills from `.claude/skills/`, and pass 1 should stay a different reviewer from pass 2.

## 2. Make it yours

- **`.github/review-policy.yml`:** replace the example `sensitive_paths` with your core paths and owning teams. Check `ignore_for_size` covers your generated code, set `deep_review.min_approvals`, and check `light_review.reviewer`.
- **`.github/CODEOWNERS`:** the same paths and teams. Keep the two in sync ([why](06-routing.md#keep-the-policy-and-codeowners-in-sync)).
- **`.github/instructions/sensitive-paths.instructions.md`:** update the `applyTo:` globs to the same paths.
- **`.github/copilot-instructions.md`:** add anything specific to your stack, such as framework conventions Copilot keeps getting wrong.
- **`.github/workflows/light-review.yml`:** if bots or coding agents open PRs in your repo, list them in `allowed_bots`.
- **`.threepass.yml`** (optional, at the repo root): pass 3's model, cost ceiling and confidence threshold. Without it, the defaults apply (`max_cost_usd: 0.50` per brief). Pass 3 reads it from the base branch. See [the tool's config](../../docs/design.md#config).

## 3. Labels and secret

```bash
bash ../three-pass-review/guide/scripts/create-labels.sh your-org/your-repo
gh secret set ANTHROPIC_API_KEY -R your-org/your-repo
```

The key is used by pass 2 (the light review) and pass 3 (the reviewer brief).

## 4. Branch ruleset

Settings → Rules → Rulesets → **New branch ruleset**. Target your default branch, set enforcement to **Active**, then turn on:

- **Require a pull request before merging**
  - Required approvals: **1**
  - **Require review from Code Owners**: this is what makes owner sign-off on sensitive paths a hard rule.
  - **Require approval of the most recent reviewable push**: stops "approve, then push something else".
  - **Dismiss stale pull request approvals when new commits are pushed**: recommended.
- **Require status checks to pass**: your CI (tests, lint, type check). These stay hard gates. Add **`review-gate`** once you go live (stage 3 of the [rollout](09-rollout.md)).
- **Automatically request Copilot code review**, with **Review new pushes**.

Optional, later: **Require conversation resolution before merging** (see [earning trust](08-earning-trust.md#later-steps-optional)).

## 5. Copilot review effort

Organization owners or repository admins can set the default effort for automatic Copilot reviews. **Lite** is enough for pass 1 if cost matters, because pass 2 does the deep structured work. Use **Balanced** if your budget allows.

## 6. Open the setup PR

Commit and open a PR. The tier check and the AI reviews **won't work on this PR**:

- The tier check runs from the base branch, where it doesn't exist yet, so it can't start pass 3 either.
- The light review reads its instructions from the base branch's `.claude/`, which isn't there yet, so it reports "didn't finish".

That's expected. Have an eng lead review the setup PR by hand, using the [deep review checklist](../templates/.github/review/deep-review-checklist.md), and merge it.

On the next ordinary PR, check that:

- [ ] a **Review tier** comment and a `tier/*` label appear within a minute,
- [ ] Copilot leaves a review,
- [ ] a **Light review (pass 2)** comment appears within a few minutes, and the tier comment's merge gate updates after it,
- [ ] adding `escalate/deep` by hand flips the tier to Deep, and removing it as the PR author puts it back,
- [ ] on that deep PR, a **Review brief** comment (pass 3) appears within a few minutes.

## Troubleshooting

| Symptom | Likely cause |
|---|---|
| No tier comment | The workflows aren't on the default branch yet. `pull_request_target` and `workflow_run` workflows run from there, so they only start working after the setup PR is merged |
| Tier job fails with "No .github/review-policy.yml on …" | The PR's base branch doesn't have the policy. Merge the kit into that branch too |
| Tier job fails parsing the policy | YAML syntax error in `review-policy.yml`. Run `yq -o=json '.' .github/review-policy.yml` locally |
| Light review skipped | The PR is a draft, comes from a fork, was opened by Dependabot, or has the `skip-light-review` label |
| Light review "didn't finish" | Missing or invalid `ANTHROPIC_API_KEY`; a bot opened the PR and isn't in `allowed_bots`; or it hit the 20-minute timeout. Open the run log from the comment |
| Light review fails with "Unknown light_review.reviewer" | `light_review.reviewer` on the base branch must be `addy` or `pr-review-toolkit` |
| Gate stays pending on a light PR | The light review hasn't finished on the latest commit, or it failed. Re-run **Light review**, or escalate |
| No reviewer brief on a deep PR | Forks and drafts get none. Otherwise check the **Review tier** run's log for "Couldn't start the deep review", and that `DEEP_REVIEW_WORKFLOW` in `review-tier.yml` names `deep-review.yml` |
| Brief says "not run" | Over the cost ceiling even after shrinking context. Raise `max_cost_usd` in `.threepass.yml` on the base branch, or split the PR |
| Brief "didn't finish" | Missing `ANTHROPIC_API_KEY`, or no pricing for the model in `.threepass.yml`. Rerun **Deep review** from the Actions tab with the PR number and **force** on |
| Gate didn't update after an approval on a fork PR | Re-run the latest **Review tier** run from the Actions tab |
| Tier says light but CODEOWNERS required an owner | The policy and CODEOWNERS have drifted. Sync them |

Back to the [README](../README.md).
