# Roadmap

Build in order. Each milestone ends with green tests and its own commit. "Done when" is the bar, not a suggestion.

## M0: Scaffold

- Gem skeleton: `three_pass_review.gemspec`, `Gemfile`, `Rakefile`, `exe/threepass`, `lib/three_pass_review.rb`, `lib/three_pass_review/version.rb`.
- Ruby 3.3+. Minitest. standardrb.
- CI: **deferred by the maintainer.** No `ruby` job is added to `.github/workflows/test.yml`; `bundle exec rake` runs locally. The existing `guide` job stays as it is.
- `.gitignore` for Ruby (`/vendor`, `/.bundle`, `/pkg`, `/coverage`).

**Done when:** `bundle exec rake` runs tests and standardrb, both green. `bundle exec exe/threepass --version` prints the version.

## M1: Diff and context

- `Diff`: parse unified diffs, including renames, deletions, binary files, multiple hunks and no-newline markers. Map each hunk to new-file line numbers.
- `ContextBuilder`:
  - excerpt each changed file from the repo checkout (hunks ± `lines_around_hunk`),
  - load conventions files for the architecture pass,
  - respect `max_excerpt_bytes`,
  - return one **frozen** base input.

**Done when:** parser tests cover the cases above with fixture diffs, and context tests use a fixture repo directory.

## M2: Passes and the LLM client

- Prompts in `lib/three_pass_review/prompts/` (`shared.md` plus one per pass). Each includes the rules from [design](design.md#the-passes) and a confidence rubric. Their hashes go into the output.
- `Finding` schema and validation.
- `LLM::Client` interface:
  - `AnthropicClient`, which forces the `report_findings` tool call and returns findings plus token usage;
  - `FakeClient`, which replays fixture responses and records every request.
- `Runner` with modes `independent` (threads), `chained`, `single` and `single_sampled`.

**Done when:**
- Tests with `FakeClient` show each mode sends the right requests.
- **The independence test passes:** in `independent` mode, no request contains another pass's output or prompt.
- One manual smoke run against the real API works when `ANTHROPIC_API_KEY` is set. Document the command; don't run it in CI.

## M3: Budget

- Estimate cost before calling, using the token-counting endpoint if the SDK has it, otherwise characters ÷ 3.5.
- Degradation order:
  1. smaller excerpts,
  2. diff only,
  3. skip the architecture pass,
  4. refuse with exit code 3.
- Actual cost from API usage, per pass.
- Pricing from config. Refuse when it's missing, unless `--no-cost-ceiling` is passed.

**Done when:** tests prove the degradation order, that the ceiling is never exceeded, and that missing pricing refuses.

## M4: Reconciler and formatters

- Implement the reconciler steps in [design](design.md#reconciler): validate, cluster, merge, score, threshold, rank, cap.
- Markdown formatter (with the `<!-- threepass -->` marker and the cost line) and JSON formatter.

**Done when:**
- Unit tests cover clustering edge cases (adjacent lines, different files, same lines with a different subcategory, the same pass repeating itself).
- Golden-file tests cover both formats.

## M5: CLI and GitHub Action

- `threepass review` with the flags from [design](design.md#inputs) and the documented exit codes.
- **Deferred by the maintainer:** `action.yml`, the dogfood workflow, and any other new file under `.github/workflows/`. The [GitHub Action](design.md#github-action) section of the design stays as the plan for when they're picked up.

**Done when:** the CLI works end to end with `FakeClient` (`THREEPASS_FAKE=fixtures/…`), and on a real diff when a key is set.

## M6: Eval harness

- Implement [eval design](eval-design.md): case loader and validator, configs, runner (3 runs each), matcher (strict and lenient), labels file with carry-over, metrics with Wilson intervals, and a report that updates the README between `<!-- eval:start -->` and `<!-- eval:end -->`.
- Rake tasks: `eval:validate`, `eval:run[config]`, `eval:report`.
- **Seed 5 cases** to prove the pipeline: 2 real, 2 planted, 1 clean. Mixed languages. Real provenance, permissive licenses.

**Done when:** `rake eval:validate` passes, and `rake eval:run[independent]` runs end to end with `FakeClient` fixtures. The report renders, and refuses precision while labels are missing. Unit tests cover the matcher, Wilson and labels.

**Stop here** and hand back to the maintainer. Don't run the real eval or publish numbers in this milestone.

## M7: Dataset and first results (needs the maintainer)

- Grow to 40 cases (see [eval design](eval-design.md#dataset)). The agent may *propose* candidates with provenance; **the maintainer confirms each one.**
- Real runs of all four configurations, 3 times each, with the maintainer's API key.
- The maintainer labels unmatched findings.
- `rake eval:report`, then update the README headline from the generated numbers only.

## M8: Plug the tool into the guide

- In `guide/`, rename the process's "passes" to **layers**: layer 1 Copilot, layer 2 agent review, layer 3 human review. That frees "passes" for the tool.
- Swap the guide's agent review (claude-code-action with a single skill) for this tool's action.
- Keep the tier check and merge gate:
  - escalate when the tool reports any critical or high finding,
  - the light-tier gate needs a clean `threepass` result on the latest commit.
- Update the guide's diagrams and site.

## Later

- Inline comments on exact lines.
- An LLM reconciler, as an eval configuration first.
- Letting the security pass search the repo for callers (needs a tool-use design and a cost model).
- Other providers.
- Caching across pushes: review only the hunks that changed since the last reviewed commit.
