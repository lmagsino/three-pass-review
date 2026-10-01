<p align="center">
  <img src="docs/images/banner.svg" alt="Three-Pass Code Review: AI reads every line. People own the risk." width="100%">
</p>

**How we review code now that agents write most of it.** Every pull request gets two AI reviews. Where a mistake would really hurt, it gets a third: an AI reviewer brief, then a deep review by people.

This repo is a written guide plus a drop-in kit for GitHub: workflows, a routing policy, the AI reviewers' instructions, a PR template and review checklists. Install it in each project and upgrade it in place. It also comes with a small website that has an interactive demo of how PRs get routed.

## How it works

<p align="center">
  <img src="docs/images/flow.svg" alt="A pull request triggers pass 1 (Copilot), pass 2 (the light review) and the tier check. The light review can escalate. The tier check sends the PR to one approval or to pass 3, the deep review, and both must pass review-gate before merge." width="100%">
</p>

| | What it does | Who | When |
|---|---|---|---|
| **Pass 1: Auto review** | Fast line comments on bugs, security, broken contracts and weakened tests, with one-click fixes | GitHub Copilot code review | Every PR, every push |
| **Pass 2: Light review** | A structured review: correctness, security, architecture, blast radius, recoverability. It reports only findings it can verify, and recommends a tier, but can only escalate | An AI reviewer of your choice: [Addy Osmani's `code-review-and-quality` skill](https://github.com/addyosmani/agent-skills/tree/main/skills/code-review-and-quality) or Claude Code's [`pr-review-toolkit`](https://github.com/anthropics/claude-code/tree/main/plugins/pr-review-toolkit) | Every ready PR, every push |
| **Pass 3: Deep review** | First an AI **reviewer brief**: the change at a high level, a change map, impact, risks, rollback, test gaps, where to look first, findings from three independent checks, and a sign-off draft. Then people verify the tests, constraints and rollback | [`threepass`](../docs/design.md#the-reviewer-brief), then the code owner and a second reviewer | Only PRs routed to deep |

The agents never approve anything. Every PR still needs a person to approve it.

## Light or deep

<p align="center">
  <img src="docs/images/tiers.svg" alt="Light review: one approver, about 5 minutes. Deep review: code owner plus a second reviewer, 30 to 60 minutes." width="100%">
</p>

A tier check labels every PR `tier/light` or `tier/deep`, using rules read from the base branch. A PR goes **deep** when it:

- touches core or sensitive paths (auth, payments, migrations, infra: you choose),
- changes the review setup itself (workflows, policy, reviewer instructions),
- deletes tests, or loosens lint, test or coverage config,
- deletes source files, or changes dependencies,
- is over 400 changed lines, or spreads across many folders,
- comes from a fork or a first-time contributor,
- or is escalated by the light review or by anyone on the team.

Automation can raise a tier but never lower one, and only a maintainer can remove an escalation. A required check called `review-gate` enforces both tiers:

- a **light** PR can't merge until the light review is clean on its latest commit;
- a **deep** PR needs two approvals of its latest commit.

## Try the router

<p align="center">
  <img src="docs/images/router-demo.png" alt="The router demo: an example PR touching src/payments is routed to deep review, and review-gate is waiting for 1 of 2 approvals." width="100%">
</p>

[`site/index.html`](site/index.html) is a one-page website for this project. Pick an example PR or type its changed files, and it shows which tier the PR lands in, why, and what still blocks the merge. It uses the same rules as the kit. Open it in a browser, or publish it with GitHub Pages (see [below](#the-website)).

## Quick start

```bash
git clone https://github.com/lmagsino/three-pass-review.git
cd your-repo
bash ../three-pass-review/guide/scripts/install.sh . --light-reviewer addy  # or pr-review-toolkit; later: --upgrade
bash ../three-pass-review/guide/scripts/create-labels.sh your-org/your-repo
gh secret set ANTHROPIC_API_KEY -R your-org/your-repo
```

Then:

1. Set your sensitive paths in `.github/review-policy.yml` and `.github/CODEOWNERS`.
2. Turn on the branch ruleset and automatic Copilot review.
3. Merge the setup PR.
4. Make `review-gate` a required check once you go live.

Step by step: **[setup](docs/setup.md)**.

## Read the guide

1. [Why review has to change](docs/01-why.md): our approach and principles
2. [The flow](docs/02-the-flow.md): the three passes, the merge gate, the labels
3. [Pass 1: Copilot](docs/03-pass-1-copilot.md)
4. [Pass 2: the light review](docs/04-pass-2-light-review.md): what it checks, choosing the reviewer, how it's kept safe
5. [Pass 3: deep review](docs/05-pass-3-deep-review.md): the reviewer brief, and how owners spend their time
6. [Routing: light or deep](docs/06-routing.md): the rules and how to tune them
7. [For authors](docs/07-for-authors.md): the PR contract, PR size, handling AI comments
8. [Earning trust](docs/08-earning-trust.md): measuring the agents, and moving areas between tiers
9. [Rollout](docs/09-rollout.md): from day one to live tiers in about a month

Plus [setup](docs/setup.md) and the [FAQ](docs/faq.md).

## What's in the repo

```
docs/                                          the guide, plus images/
site/index.html                                the website, with the router demo
templates/                                     copy into your repo (install.sh does it)
  .github/
    review-policy.yml                          routing rules: sensitive paths, thresholds, approvals
    CODEOWNERS                                 who signs off on sensitive paths
    copilot-instructions.md                    what pass 1 focuses on
    instructions/sensitive-paths.instructions.md
    pull_request_template.md                   the author's side of the contract
    review/approval-checklist.md               the 5-minute approval on light PRs
    review/deep-review-checklist.md            the owner's deep review
    workflows/review-tier.yml                  tier check + review-gate; starts pass 3
    workflows/review-submitted.yml             re-checks the gate when someone approves
    workflows/light-review.yml                 pass 2
    workflows/deep-review.yml                  pass 3: the reviewer brief, from threepass
    scripts/review-tier.mjs                    the tier rules and gate
    scripts/post-light-review.sh               posts the light review summary, escalates
    scripts/post-deep-review.sh                posts the reviewer brief
  .claude/review/
    light-review.md                            pass 2 protocol
    methods/addy.md, methods/pr-review-toolkit.md   one method per reviewer choice
    skills/code-review-and-quality/            Addy's skill, pinned (fetched by the vendor script)
scripts/
  install.sh                                   install the kit into a repo, or --upgrade it
  vendor-addy-skill.sh                         fetch the review skill at a pinned commit
  create-labels.sh                             create the labels
tests/review-tier.test.mjs                     node --test
```

## Design choices

- **Two different AI reviewers.** Different tools catch different bugs. The pass 2 skill sits in `.claude/review/skills/` rather than `.claude/skills/`, so Copilot doesn't load it and the two passes stay different.
- **AI reviews are sensors, not verdicts.** The AI reviewers can't approve, push or change labels. It returns its verdict as data, and a plain script acts on it.
- **Escalate only.** The light review and people can move a PR to deep. Nothing automated can move it back, and if the PR's author removes an escalation, it's put back.
- **A PR can't change its own reviewer.** The rules, the choice of light reviewer, the reviewer instructions and pass 3's cost ceiling are all read from the base branch. Any PR that touches the review setup goes to deep.
- **A failed review is never a clean one.** The gate needs a clean light review of the exact latest commit.
- **Automation prepares, people decide.** On deep PRs the reviewer brief does the reading and organizing, so the owner's time goes to judgment. It never approves or blocks.
- **One setup, many projects.** The installer pins every AI piece to a known version and upgrades a project in place, leaving the team's own files alone.
- **GitHub's own rules are the hard guarantees.** CODEOWNERS, required approvals, and approval of the most recent push. The gate makes the right path the easy one ([what it does and doesn't protect against](docs/06-routing.md#what-the-gate-does-and-doesnt-protect-against)).

## The website

`site/index.html` is a single static page with no build step. To publish it:

1. Push the repo to GitHub.
2. Go to **Settings → Pages** and set **Source** to **GitHub Actions**.

The repo's `.github/workflows/pages.yml` then deploys it on every push to `main`.

## Credits

- **Pass 2** uses Addy Osmani's [`code-review-and-quality`](https://github.com/addyosmani/agent-skills/tree/main/skills/code-review-and-quality) skill from [agent-skills](https://github.com/addyosmani/agent-skills) (MIT). The kit downloads it at a pinned commit, with its license notice, rather than copying it into this repo.
- **Pass 2 runs on** [anthropics/claude-code-action](https://github.com/anthropics/claude-code-action), and can use Claude Code's [`pr-review-toolkit`](https://github.com/anthropics/claude-code/tree/main/plugins/pr-review-toolkit) plugin instead of the skill.
- **Pass 3 is** [`threepass`](../README.md), in this repository.
- **Pass 1 is** [GitHub Copilot code review](https://docs.github.com/en/copilot/how-tos/use-copilot-agents/request-a-code-review/use-code-review).

Not affiliated with or endorsed by Addy Osmani, GitHub or Anthropic.

## License

MIT. See [LICENSE](../LICENSE). Contributions welcome: see [CONTRIBUTING](CONTRIBUTING.md).
