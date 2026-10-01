# Eval design

The eval is what makes this project worth anything. Every number in the README comes from `rake eval:report` run against the public dataset in `evals/`. No number is typed by hand, and no number is published before its findings are labeled by a person.

## Questions the eval answers

1. **Recall:** of the known defects in a PR, how many does each pass, and the reconciled output, report? Broken down by category and subcategory.
2. **Precision:** of what it reports, how much is real? Measured on PRs with known defects and on clean PRs.
3. **Shape:** do independent passes beat chained passes, and a single pass at similar or lower cost? That's [ADR 0001](decisions/0001-independent-passes.md); this eval decides it.
4. **Cost:** what does one review cost, at the median and the 90th percentile, and how often does the ceiling kick in?
5. **Stability:** how much do results change between identical runs?

## Dataset

Target 40 cases (MVP minimum 30), in three kinds:

| Kind | Target | What it is | Why |
|---|---|---|---|
| `real` | 20 | A real PR from a public repo that introduced a bug, later fixed by a known fix commit | Realistic bugs and realistic surrounding code |
| `planted` | 10 | A clean real PR with exactly one bug deliberately inserted | Exact ground truth, and the model can't have seen it during training |
| `clean` | 10 | A real merged PR with no known defects | Measures false positives where there's nothing to find |

Spread across:

- **Languages:** at least Ruby, Python, TypeScript and Go.
- **Categories:** each pass needs at least 8 defects in its own category, or its recall number is meaningless.

### Finding real cases

1. **Start from fixes.** Use advisories (GitHub Security Advisories, CVEs that link a fix commit) for security bugs. For correctness bugs, use fix commits or PRs whose message names the bug ("fix off-by-one", "handle nil").
2. **Trace back to the PR that introduced the bug.** Run `git blame` on the lines the fix changed, at the fix's parent commit. This is the SZZ approach, and it's noisy, so **a person confirms every trace** by reading both diffs. Discard anything ambiguous.
3. **Prefer recent bugs.** Introducing PRs merged after the model's training cutoff can't be memorized. Record the merge date, and report results for before-cutoff and after-cutoff cases separately.
4. **Permissive licenses only** (MIT, Apache-2.0, BSD). Record the license and links in the case file.

### Making planted cases

Take a clean real PR and add one small, plausible bug that looks like it belongs in the diff. Keep a catalog so the types are balanced, for example:

- a missing authorization check,
- string-built SQL or a shell command,
- an off-by-one in a loop or slice,
- a missing nil or empty check,
- swapped arguments,
- a swallowed error,
- a missing `await` (or async equivalent),
- logging a secret or PII,
- a user-supplied URL fetched server-side,
- a new helper that duplicates an existing one (architecture).

### Finding clean cases

Merged PRs whose changed lines weren't touched by any fix commit for at least six months after merge. These are "probably clean", not "certainly clean", so findings on them still get labeled.

### Case format

```
evals/cases/<id>/
  case.yml        metadata and ground truth
  diff.patch      unified diff of the PR
  context/        head-version copies of changed files (and conventions files), so runs need no network
```

```yaml
id: rb-sqli-001
kind: real                     # real | planted | clean
language: ruby
source:
  repo: https://github.com/example/app
  license: MIT
  pr: https://github.com/example/app/pull/1234
  introduced_by: 4f2a9c1       # merge or head commit of the PR under review
  fixed_by: 9b77e02            # for real cases
  merged_at: 2026-07-14
pr:
  title: "Add sortable columns to invoices index"
  body: |
    Lets users sort invoices by any column.
defects:                       # empty for clean cases
  - id: d1
    file: app/controllers/invoices_controller.rb
    lines: [42, 44]            # in the new version of the file
    category: security
    subcategory: sql_injection
    severity: high
    description: "params[:sort] interpolated into ORDER BY."
notes: "Fix commit allow-lists sort columns."
```

`rake eval:validate` checks every case: the schema, a permissive license, that the diff parses and applies to `context/` (every added line is at its line number in the head-version copy), and that each defect's lines fall inside a changed hunk. Planted cases also need a `notes` entry saying how the bug was planted, and real cases need `fixed_by`.

## Matching findings to defects

A reconciled finding **matches** a defect when:

1. it's in the same file,
2. its line range overlaps the defect's lines, allowing a gap of up to 3 lines, and
3. its category matches. A matching subcategory is recorded too, but not required.

Report two numbers: **strict** (all three conditions) and **lenient** (file and lines only). One finding can match at most one defect, and one defect counts as caught once. Findings are matched in the reviewer's own ranking order, so a defect goes to the highest-ranked finding that hits it.

**Across the 3 runs**, a defect counts as caught when it's caught in a majority of its case's runs. That keeps n equal to the number of defects, so the Wilson interval means what it says. Pooling every run instead would triple n and make the interval look three times as certain as the data allows. The per-run spread is reported as stability.

Anything that matches no defect, even leniently, is **unmatched**. Unmatched isn't automatically wrong, because PRs often have real problems nobody wrote down. A finding on a defect's lines with the wrong category counts as matched for precision, since it points at a real problem, but only lenient recall gives it credit.

## Labeling (what makes precision honest)

1. `rake eval:run` writes every unmatched finding to `evals/labels/<run-id>.yml` with `label: unlabeled`. That covers the reconciled findings and each pass's own findings before reconciliation, since per-pass precision needs both.
2. A person labels each one:
   - `real`: a real problem that isn't in the ground truth,
   - `false_positive`: wrong,
   - `nitpick`: true, but not worth a comment,
   - `unclear`.
3. Labels are keyed by a hash of the case, file, lines and title, so they carry over to later runs when the same finding appears again.
4. `rake eval:report` refuses to print precision while more than 5% of findings are unlabeled. Until then it reports "unverified findings per PR". It rescores every run with the current labels, so labeling after a run is enough; there's no need to re-run.

**Precision** = (matched + `real`) ÷ (all reconciled findings − `unclear`), pooled over every run.

## Configurations compared

Each configuration runs on every case, **3 times**, because model output varies from run to run.

| Config | What runs | Question it answers |
|---|---|---|
| `independent` | 3 passes in parallel, none sees the others, deterministic reconciler | The product |
| `chained` | Pass 2 sees pass 1's findings; pass 3 sees both. Same reconciler | Do later passes anchor on earlier findings and miss things? |
| `single` | One pass with a combined prompt covering all three areas | Is splitting into three passes worth it at all? |
| `single_sampled` | The combined prompt run 3 times independently, same reconciler | Is the gain from *specialized* passes or just from *sampling three times*? This is the cost-matched control |

Also report:

- **Per-pass recall before reconciliation,** for `independent` and `chained`. Does a pass find bugs in its own category? Does it find bugs outside it?
- **A threshold sweep:** precision and recall at confidence thresholds 0.3 to 0.9, to show the trade-off and justify the default. It's computed by re-reconciling each run's raw pass findings at each threshold, so it needs no extra API calls.

## Metrics and statistics

| Metric | Definition |
|---|---|
| Recall (overall, per category, per subcategory) | Caught defects ÷ defects |
| Precision | See above |
| False positives per clean PR | `false_positive` labels on clean cases ÷ reviews of clean cases (clean cases × runs), so it reads as "per review of a clean PR" |
| Unverified findings per PR | Unlabeled unmatched findings ÷ reviews (cases × runs), shown until labeling is done |
| Cost per review | USD per case: median, p90, max |
| Ceiling hits | Cases where the cost ceiling degraded or refused the review |
| Latency | Seconds per review: median, p90 |
| Stability | Recall range (min to max) across the 3 runs |

**Uncertainty is part of the number:**

- Every proportion gets a 95% Wilson score interval, and n is always shown.
- Per-subcategory numbers with n < 8 are listed as counts ("5 of 7"), never as percentages.
- When comparing configurations, call a difference real only if the intervals don't overlap. Otherwise say "no clear difference", which is a legitimate result.

## Reproducibility

Every run records:

- the model ID and sampling settings,
- the prompt file hashes,
- the dataset version (a hash of `evals/cases/`),
- the code version (git SHA),
- the config,
- the date.

Results go in `evals/results/<date>-<config>-<model>/`, containing `records.json` (the raw output of every review), `summary.json`, `summary.md` and `misses.md`. Each run's metadata says which client produced it.

Two guards keep invented numbers out of the README:

- **Fake runs never reach it.** `EVAL_FAKE=DIR rake eval:run[...]` replays fixture responses, writes to `tmp/eval-fake/`, and is marked `client: fake`. `eval:report` publishes only runs marked `client: anthropic`.
- **Runs on an older dataset version aren't published.** If cases change after a run, it has to be re-run.

A real `rake eval:run` makes no API calls unless `CONFIRM=yes` is set. Without it, the task prints the most the run could spend (cases × runs × `max_cost_usd`) and stops.

Anyone can rerun everything with their own API key:

```bash
bundle exec rake eval:run[independent]   # and chained, single, single_sampled
bundle exec rake eval:report             # also updates the README table between its markers
```

`rake eval:report` rewrites only the block between `<!-- eval:start -->` and `<!-- eval:end -->` in the README.

## Harness layout

```
evals/
  README.md            how to run, how to label, how to add a case
  cases/<id>/          dataset
  configs/             independent.yml, chained.yml, single.yml, single_sampled.yml
  labels/              human labels for unmatched findings
  results/             committed summaries (raw outputs can be gitignored if large)
lib/three_pass_review/eval/
  case.rb (case, defect, dataset loader and version), matcher.rb, labels.rb, metrics.rb (incl. Wilson),
  scorer.rb (all the metrics above), summary.rb, runner.rb, report.rb
```

Unit tests cover the matcher, Wilson intervals, label carry-over and the report writer, all with fixtures and no network.

## What we'll say about the results

- **Lead with recall and precision per category, with intervals and n.** Not one cherry-picked number.
- **Report the comparison honestly.** If `single_sampled` matches `independent`, say so and change the design.
- **Say what the bot can't catch.** Bugs that need runtime state, cross-service context, product intent or files outside the diff. Each missed defect gets a one-line reason in `evals/results/.../misses.md`. That list is the third blog post.
