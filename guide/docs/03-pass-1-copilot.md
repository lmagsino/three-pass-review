# 3. Pass 1: Copilot auto review

**Job:** fast, broad, line-level feedback on every push, with fixes the author can apply in one click.

Copilot is the first sensor. It's quick, it's already in the PR view, and its suggestions can be committed straight from the comment. It isn't the reviewer of record. By default it leaves a "Comment" review, not "Approve" or "Request changes", so it doesn't count toward required approvals.

## Turn it on

**For the repository (recommended):** Settings → Rules → Rulesets → New branch ruleset, targeting your default branch:

- Turn on **Automatically request Copilot code review**.
- Turn on **Review new pushes**, so Copilot re-reviews after every push instead of only once.

Individuals can also turn on **Automatic Copilot code review** in their own Copilot settings, which covers every PR they open, in any repo.

Copilot code review can be enabled for organization members without a Copilot license, by an enterprise administrator or organization owner.

**By hand, when you need it:** click **Request** next to Copilot under Reviewers, or:

```bash
gh pr create --reviewer @copilot
gh pr edit 123 --add-reviewer @copilot
```

## Review effort

Copilot offers two effort levels: **Lite** (cheaper, targets glaring bugs, security issues and style slips) and **Balanced** (a higher-reasoning model, deeper on complex logic and cross-service changes). Organization owners and repository admins can set the default for automatic reviews.

In this setup, pass 2 does the deep structured work, so **Lite** is a reasonable default for pass 1 if you watch costs. Use **Balanced** if your budget allows; two strong, different reviewers catch more than one.

## Tell it what to focus on

Copilot reads, from the repository:

| File | Use it for |
|---|---|
| `.github/copilot-instructions.md` | Repo-wide review guidance. Template: [copilot-instructions.md](../templates/.github/copilot-instructions.md) |
| `.github/instructions/*.instructions.md` | Extra guidance for matching paths, set with `applyTo:` front matter. Template: [sensitive-paths.instructions.md](../templates/.github/instructions/sensitive-paths.instructions.md) |
| `AGENTS.md` | Context about how the project works and which patterns are intentional |
| `CLAUDE.md`, `GEMINI.md`, `REVIEW.md` | Copilot reads these too, if they exist |
| `.github/skills/`, `.claude/skills/`, `.agents/skills/` | Agent skills Copilot can use during review |

The template instructions keep pass 1 in its lane: bugs, security, broken contracts, weakened tests, data and performance. They tell it to skip formatting that linters already handle, and to stay quiet unless it's confident.

**Watch out:** Copilot reads these files from the PR's **head** branch, so a PR can change the instructions used to review it. That's handy for testing instruction changes, and it's also why the tier check routes any change to these files to deep review.

**Keeping the two reviewers different:** because Copilot loads skills from `.claude/skills/`, the kit keeps the pass 2 review skill in `.claude/review/skills/` instead. Pass 2 reads it by path, and Copilot doesn't pick it up, so pass 1 stays a genuinely different reviewer.

## How authors handle Copilot comments

- Each comment carries a severity: High, Medium or Low. Fix High ones or reply with why not.
- Apply small fixes straight from the suggestion, or batch several into one commit.
- Copilot doesn't read replies, so don't argue with it. If it's wrong, resolve the thread with a short note for the human reviewer, and use 👎 to send feedback.
- On re-review, Copilot may repeat a comment you already resolved. Resolve it again.

## What pass 1 is not

- **Not an approval.** Even when Copilot finds nothing, a human still approves.
- **Not the only AI review.** Copilot and the pass 2 agent are different models with different instructions on purpose, because different reviewers catch different bugs.
- **Not a replacement for CI.** Tests, linters, type checks and security scanners stay as hard, deterministic gates.

## Copilot approvals (preview, later)

GitHub has a public preview where Copilot can submit an approving review that counts toward required approvals. It's off by default, and repository admins can limit which file paths Copilot approvals count for. Don't turn this on at the start. It's a step for later, for specific low-risk paths that have earned it. See [earning trust](08-earning-trust.md).

Next: [pass 2, the agent review](04-pass-2-agent-review.md).
