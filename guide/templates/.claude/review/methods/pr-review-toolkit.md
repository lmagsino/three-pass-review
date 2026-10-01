# Method: Claude Code's pr-review-toolkit

The `pr-review-toolkit` plugin (from `anthropics/claude-code`) is installed for this run. Its specialist agents are your first readers. You are the editor: everything they report is a candidate, and only what you verify yourself ("Verify before you report" in the ground rules) goes into the review.

## Run the specialists

Start each one with the `Task` tool. Give it the PR number and these instructions: "Review only this PR's diff (`gh pr diff <PR>`). Report each finding with `path:line` and evidence. Don't edit files and don't post comments."

Always run:

- `pr-review-toolkit:code-reviewer`: bugs, quality, and the project's own guidelines (`CLAUDE.md` and similar)
- `pr-review-toolkit:silent-failure-hunter`: swallowed errors, bad fallbacks, missing error handling
- `pr-review-toolkit:pr-test-analyzer`: whether the tests cover the changed behavior

Run these only when the diff calls for them:

- `pr-review-toolkit:type-design-analyzer`: new or changed types
- `pr-review-toolkit:comment-analyzer`: added or changed comments and docs

Don't run `code-simplifier`. It proposes rewrites, and this review never changes code.

## Cover what the toolkit doesn't

The toolkit has no security or performance specialist. Do those reads yourself, correctness and security first:

- injection,
- missing authorization,
- secrets or personal data in code or logs,
- unbounded work on user input,
- N+1 queries.

## Map to this review's severities

- A finding that breaks behavior, security or data: **Critical**.
- A real bug or a missing test for changed behavior: Required (no prefix).
- An improvement worth making: **Consider**.
- Style or naming: **Nit**. These go in the summary as a count only.
