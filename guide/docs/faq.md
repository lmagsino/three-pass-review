# FAQ

**Isn't it risky to skip deep human review on some PRs?**
Every PR still gets two AI reviews and a human approval. What light-tier PRs skip is the 30–60 minute deep read, and only when deterministic rules say the blast radius is low *and* both AI reviews are clean. The alternative is often worse: when everything needs a deep read, people start skimming everything.

**Why two AI reviewers instead of one good one?**
They catch different things. Two copies of the same model mostly repeat each other. Copilot plus a different agent running a different method overlap far less.

**Why can't the agent lower a tier?**
Because the agent reads untrusted input. A PR could contain text written to talk it into "this is trivial". If the agent can only escalate, the worst a manipulated agent can do is stay quiet. Then the floor rules, Copilot and a human approver are still there.

**What if Copilot and the agent disagree?**
That's useful information, not a problem. The agent's summary notes where it thinks Copilot is wrong. The human decides. If the disagreement is about something risky, escalate.

**What does it cost?**
Pass 1 uses your Copilot plan. Pass 2 is one agent session per push on ready PRs, paid on your Anthropic account (or your cloud provider). Drafts are skipped and superseded runs are cancelled. Compare the bill with an hour of senior review time per deep PR, and with the cost of one incident.

**We don't use Copilot / don't have an Anthropic key.**
The structure matters more than the vendors.
- **Pass 1:** swap in any automatic PR reviewer.
- **Pass 2:** swap in any coding agent that can run in CI, read the markdown prompt and skill, and return a structured result.

Keep the two reviewers different, and keep the light reviewer read-only and escalate-only. Pass 2 already lets you choose between Addy's skill and Claude Code's `pr-review-toolkit`; see [choosing the reviewer](04-pass-2-light-review.md#choosing-the-reviewer).

**Does this work on GitLab or Bitbucket?**
The process does. The templates are GitHub-specific: Actions, rulesets, CODEOWNERS, Copilot review. You'd port the tier script (it only needs a list of changed files with line counts) and the workflows.

**What about open source projects with fork PRs?**
The tier check works on forks (it uses `pull_request_target` safely; see [routing](06-routing.md#why-pull_request_target-is-safe-here)). The light review and the reviewer brief skip forks, because fork runs don't get secrets and the safe alternatives are fiddly. So fork PRs go to deep review. A maintainer can run the same skill locally to prepare that review, and trusted regulars can be given branch access so their PRs get pass 2.

**Our juniors learned by reviewing. Doesn't this take that away?**
It can, if you let it. Deep reviews are where knowledge transfer now happens on purpose. Rotate juniors through them as second reviewers, and have them write the sign-off note. A light-tier approval also isn't "nobody reads it". It's a focused 5-minute check, and juniors can do those from day one.

**Can blast radius be measured better than paths and line counts?**
Yes. Tools that build a call graph of what a PR changed (which functions and classes changed shape, and every caller) measure it directly. The policy here uses file-level proxies because they're cheap and can't be argued with, and the agent searches for real callers on top. If you add a graph tool, feed its output in as one more escalation signal.

**Does this replace CI?**
No. Tests, type checks, linters and security scanners stay as hard gates that nothing can override. The AI reviews are sensors that sit on top of them. The tier check also watches for changes that weaken the gates: deleted tests and edited lint or coverage config both go to deep.

**How do we update the review skill?**
Rerun `scripts/vendor-addy-skill.sh` with a newer commit SHA, read the diff of `.claude/review/skills/`, and open a PR. It touches `.claude/`, so it gets a deep review, which is the right amount of care for changing how every PR is reviewed.

**Who made the review skill?**
Addy Osmani. Pass 2 uses his MIT-licensed [`code-review-and-quality`](https://github.com/addyosmani/agent-skills/tree/main/skills/code-review-and-quality) skill from [agent-skills](https://github.com/addyosmani/agent-skills). The vendor script copies it in with its license notice. This project isn't affiliated with or endorsed by him.
