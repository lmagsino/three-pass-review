---
description: Build threepass from the specs, milestones M0 to M6
---

You're implementing `threepass` in this repo. Before writing any code, read these in full:
CLAUDE.md, README.md, docs/design.md, docs/eval-design.md, docs/decisions/0001-independent-passes.md and docs/roadmap.md.

If this folder isn't a git repository yet, run `git init` and commit the existing files as "Specs and guide" before starting.

Then implement roadmap milestones M0 through M6, in order. For each milestone:
1. Write a short plan for it (a few bullets) before coding.
2. Implement it until every item in its "Done when" holds.
3. Run `bundle exec rake` until it's green (tests and standardrb), and keep `(cd guide && node --test)` green.
4. Commit with the message "M<n>: <one-line summary>".

Follow the non-negotiables in CLAUDE.md. In particular:
- In independent mode, passes never see each other's output, and there's a test that proves it.
- No network calls in tests. Use the fake client with fixtures.
- Never put invented numbers in the README or docs. The results table only changes through `rake eval:report`.
- The cost ceiling is enforced exactly as docs/design.md describes.
- Check model IDs, prices and SDK capabilities against Anthropic's current docs instead of memory. Before choosing the client, check whether the official `anthropic` Ruby gem supports Messages with forced tool use, token usage and token counting. Use it if so, otherwise `net/http`.

For the M6 seed cases (2 real, 2 planted, 1 clean), use only public repos under MIT, Apache-2.0 or BSD licenses, record provenance in each case.yml, and keep a list of anything you couldn't fully verify.

If a spec turns out to be wrong or unclear, fix the spec in the same commit and say why in the commit message.

Stop after M6. Don't run the real eval, and don't publish any numbers. When you stop, report:
- what's done in each milestone, and the test count,
- anything you did differently from the specs, and why,
- one smoke-test command I can run with my own API key,
- exactly what I need to do for M7 (dataset growth, real runs, labeling).

$ARGUMENTS
