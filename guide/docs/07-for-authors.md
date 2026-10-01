# 7. For authors

Reviewers can only move fast if authors do their part. Your job is to deliver code you've proven works, whether you typed it or an agent did.

## The PR contract

The PR contract is what the author owes the reviewer. The [PR template](../templates/.github/pull_request_template.md) asks for each part:

| Element | What to write |
|---|---|
| **What and why** | 1–2 sentences. What changes for users or callers, and why now |
| **Proof it works** | Tests added or changed, commands run, screenshots or logs. "CI is green" isn't proof on its own |
| **Risk and AI role** | Blast radius, how to roll back, and which parts an agent wrote |
| **Key decisions** | What you (or the agent) chose, and what else was considered |
| **Review focus** | The 1–2 places you most want human judgment |

Agent PRs often arrive without the reasoning behind them, so the reviewer has to reconstruct it. Writing down the key decisions saves them that work. The agent review treats a missing "what and why" or missing proof as a Required finding, so skipping either costs you a round trip.

## Keep it small

From the review skill's change-sizing guidance:

| Size | Verdict |
|---|---|
| ~100 changed lines | Good. Reviewable in one sitting |
| ~300 changed lines | Fine, if it's one logical change |
| ~1,000 changed lines | Too big. Split it |

The tier check makes this concrete: over 400 lines goes to deep review, and over 1,000 adds `needs-split`. Agents tend to produce big PRs, so ask yours for small slices up front.

**How to split** (from the same skill):

| Strategy | How | When |
|---|---|---|
| Stack | Land a small change, build the next one on it | Steps depend on each other |
| By file group | Separate PRs for parts that need different reviewers | Cross-cutting work |
| Horizontal | Shared code and stubs first, then the code that uses them | Layered architecture |
| Vertical | Thin end-to-end slices of the feature | Feature work |

**Keep refactoring and behavior changes apart.** A PR that moves code *and* changes what it does is two PRs. A pure move is easy to review. A pure behavior change is easy to review. Mixed, both get hard.

## Before you open the PR

1. **Read every line you're asking someone else to approve.** If an agent wrote it, you're its first reviewer.
2. **Run an agent review locally.** With Addy Osmani's agent-skills installed in Claude Code (`/plugin marketplace add addyosmani/agent-skills`, then `/plugin install agent-skills@addy-agent-skills`), run `/review`. Fix what it finds before anyone else spends time on it. The same skill works in other agents; see [agent-skills](https://github.com/addyosmani/agent-skills#quick-start).
3. **Fill in the PR template.** Especially rollback and review focus.
4. **Open as draft** while you iterate. The agent review skips drafts, so you don't pay for reviews of half-finished work. Mark it ready when it is.

## Handling AI review comments

- **Critical and Required:** fix them, or reply with evidence that they're wrong. Never resolve one silently.
- **Consider, Nit, FYI:** your call. A short reply ("leaving as is because…") helps the human reviewer.
- **Copilot doesn't read replies.** Resolve its threads with a note for the human, and use 👎 if it was wrong.
- **Disagree with an escalation?** Say why in a comment. A maintainer can remove `escalate/deep`. You can't (the tier check puts it back), and opening a new PR to dodge it isn't on.
- **Think it should be deeper than the bot says?** Add `escalate/deep` yourself. Nobody will mind.

## Disclosing AI involvement

Say which parts an agent wrote and what you checked yourself. The point isn't blame. It tells the reviewer where nobody has read the code yet. "Agent wrote the CSV export; I reviewed it and added the edge-case tests" is all it takes.

Next: [earning trust](08-earning-trust.md).
