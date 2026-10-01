## What and why

<!-- 1–2 sentences. What changes for users or callers, and why now. -->

## Proof it works

<!-- Tests added or changed, commands you ran, and screenshots or logs for anything visible.
     "CI is green" is not proof on its own. -->

## Risk and AI involvement

- **Blast radius:** <!-- What calls the code you changed? Any schema, data, public API or config changes? -->
- **Rollback:** <!-- Plain revert is enough / behind a feature flag / needs a down-migration / not reversible (explain) -->
- **AI-written parts:** <!-- Which parts an agent wrote, and what you checked yourself. "None" is a fine answer. -->

## Key decisions

<!-- What was decided, and what else was considered. If an agent wrote this, what did it choose and why?
     The reviewer shouldn't have to reconstruct your reasoning from the diff. -->

## Review focus

<!-- The 1–2 places where you most want human judgment. -->

## Author checklist

- [ ] I've read every line I'm asking someone else to approve.
- [ ] I ran an agent review myself before opening this (for example `/review` from addyosmani/agent-skills).
- [ ] Under ~400 changed lines, or I've explained above why it can't be split.
- [ ] Refactoring and behavior changes are in separate PRs.

<!-- The review-tier bot labels this PR light or deep. If you think it should be deep, add the escalate/deep label. -->
