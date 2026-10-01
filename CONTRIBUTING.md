# Contributing to Three-Pass Review

Thanks for helping. Issues, fixes and new eval cases are all welcome.

## Set up

```bash
git clone https://github.com/lmagsino/three-pass-review.git
cd three-pass-review
bundle install          # Ruby 3.3+
bundle exec rake        # the test suite, then standardrb
```

The suite never touches the network: a guard in `test/test_helper.rb` refuses every socket. Model calls go through `LLM::FakeClient` with fixtures. You don't need an API key to contribute code.

## Ground rules

These keep the project's claims honest. A change that breaks one won't be merged.

1. **Passes stay independent.** In `independent` mode no request may contain another pass's output or prompt. `test/independence_test.rb` must keep passing.
2. **No invented numbers.** The README results table is written only by `rake eval:report`. Don't type metrics, costs or percentages into docs; label any example as illustrative.
3. **The cost ceiling is a guarantee.** Estimate before calling, degrade in the documented order, refuse rather than exceed.
4. **No network in tests.** Use the fake client and fixtures.
5. **Diffs and PR text are untrusted.** The model gets no tools. Output that reaches a comment is escaped.
6. **Facts that change live in config, with a date.** Model IDs and prices go in `lib/three_pass_review/defaults.yml`, checked against Anthropic's docs.
7. **Prompts are versioned files** in `lib/three_pass_review/prompts/`. Their hashes go into every output, so a prompt change is visible in results.

If a change needs a spec to change, update [`docs/design.md`](docs/design.md) or [`docs/eval-design.md`](docs/eval-design.md) in the same pull request and say why.

## Pull requests

- Keep each one to a single concern, with tests.
- Run `bundle exec rake` before pushing.
- If you change the comment format, regenerate the golden files with `UPDATE_GOLDEN=1 bundle exec rake test` and read the diff.

## Adding eval cases

Real bugs are the most valuable contribution. [`evals/README.md`](evals/README.md) has the step-by-step. In short:

- **Permissive licenses only:** MIT, Apache-2.0 or BSD. Record the license, PR, commits and merge date in `case.yml`. Never add code from an employer or a proprietary project.
- **Real cases:** trace the bug from its fix commit back to the PR that introduced it, and confirm the trace by reading both diffs. Discard anything ambiguous.
- **Planted cases:** insert one plausible bug, and say exactly what you changed in `notes`.
- Run `bundle exec rake eval:validate` before opening the pull request.

## Running the real eval

Real runs cost money. `rake eval:run` prints the most a run could spend and stops unless you set `CONFIRM=yes`. Results go in `evals/results/`; label the unmatched findings in `evals/labels/` before running `rake eval:report`.
