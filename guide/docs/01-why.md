# 1. Why review has to change

Agents write code faster than people can read it. Teams usually react in one of two ways, and both fail:

- **Keep reading every line.** Review becomes the bottleneck. PRs wait for days, and reviewers burn out.
- **Quietly stop reading.** Review becomes a rubber stamp. Bugs, security holes and code nobody understands get merged.

The fix isn't more reviewers. It's spending human attention where it pays, and letting machines cover the rest.

## What review is for now

Review used to check the author's reasoning. The author understood the change, and the reviewer checked their work. With an agent-written PR, often nobody has worked out the "why" yet. The reviewer may be the first person to read the code at all.

So review now has three jobs:

1. **Catch defects.** Machines are good at this, and different machines catch different things.
2. **Recover intent and build understanding.** Someone on the team has to understand the code well enough to own it, debug it and change it later.
3. **Decide what's safe to ship.** That depends on what a mistake would break, and it stays with a person.

## Our approach

**AI reads every line. People own the risk.**

1. **Every PR gets two AI reviews.**
   - Copilot leaves fast line comments on every push.
   - A second, different agent runs a structured review. It uses Addy Osmani's [`code-review-and-quality`](https://github.com/addyosmani/agent-skills/tree/main/skills/code-review-and-quality) skill.

   Together they find bugs, verify them, rank them by severity and suggest fixes.
2. **Low-risk PRs get a light human review.** If a change touches ordinary code and both AI reviews are clean, one person approves it after a 5-minute check.
3. **High-risk PRs get a deep human review.** Core and sensitive paths, and anything with a wide blast radius, go to the code owner and a second reviewer. They spend their time on verification, constraints and rollback.

## The principles

1. **Two different AI reviewers, not one.** Different models with different instructions catch different bugs. Two copies of the same reviewer mostly repeat each other.
2. **AI reviews are sensors, not verdicts.** The agents never approve. They tell a person where to look.
3. **Depth follows blast radius, not the author.** A one-line change to payments gets more attention than a 300-line change to an internal admin page.
4. **Rules set the floor, and AI can only raise it.** Deterministic rules, read from the base branch, decide the minimum tier. An agent can escalate a PR to deep review. Nothing automated can lower one.
5. **Authors owe proof.** No PR goes up without what and why, evidence it works, and the key decisions behind it.
6. **Small PRs.** About 100 changed lines is good, about 300 is fine for one logical change, and about 1,000 is too big to review properly.
7. **Trust is earned per area, with data.** Areas move from deep to light review when the record supports it, and move back after an incident.
8. **Keep recoverability.** Anything a plain revert can't undo always gets a deep review.

Next: [the flow](02-the-flow.md).
