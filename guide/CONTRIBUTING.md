# Contributing

Thanks for helping. This guide gets better with real-world numbers and failure stories.

## Most useful contributions

- **Field reports.** What tier mix, agent precision and escaped-defect numbers did you see after a month? What did you change in the policy, and why? Open an issue with the `field-report` label.
- **Policy presets** for common stacks (Rails, Django, Next.js, Go services, monorepos): sensitive paths, generated folders, dependency and quality-gate files.
- **Ports** of the workflows to other CI systems or other pass-2 agents. Keep the properties in [swapping the agent](docs/04-pass-2-agent-review.md#swapping-the-agent).
- **Fixes** to anything that's wrong or out of date. GitHub and the agent tools change fast.

## Ground rules

- Keep the safety properties. Every change must keep these true:
  - Escalate only.
  - Rules come from the base branch.
  - No PR code runs in `pull_request_target`.
  - The agent is read-only and returns its verdict as data.
- Change the tier rules? Add or update a test in `tests/review-tier.test.mjs` and run `node --test` from `guide/`.
- Credit third-party skills and tools by name and license, and keep their license notices with any copied files.
- Plain language. The docs are read by busy reviewers.
