# code-review-and-quality (vendored)

This folder holds a pinned copy of Addy Osmani's **code-review-and-quality** skill from [addyosmani/agent-skills](https://github.com/addyosmani/agent-skills) (MIT). The light review (pass 2) follows it when `light_review.reviewer` is `addy`.

It isn't included in this template. Fetch it with:

```bash
bash scripts/vendor-addy-skill.sh /path/to/your/repo
```

That writes:

- `.claude/review/skills/code-review-and-quality/SKILL.md`
- `.claude/review/references/security-checklist.md` and `performance-checklist.md` (the skill links to them)
- `.claude/review/THIRD_PARTY_NOTICES.md` with the source commit and the MIT license

## Why a pinned copy instead of installing the plugin in CI

- **Stable reviewer.** An upstream edit doesn't silently change how your PRs get reviewed. You update on purpose, in a PR, and that PR gets a deep review because it touches `.claude/`.
- **Nothing executable.** The full plugin includes hooks that run commands. A CI job that holds an API key and a write token should only load plain markdown.
- **Not auto-loaded.** It lives in `.claude/review/skills/`, not `.claude/skills/`. Copilot and Claude Code auto-load skills from `.claude/skills/`, and pass 1 (Copilot) should stay a different reviewer from pass 2. The pass 2 prompt reads this file by path.
- **Trusted copy.** `claude-code-action` restores `.claude/` from the base branch before it starts, so a PR can't edit the skill that reviews it.

You can delete this README after vendoring.
