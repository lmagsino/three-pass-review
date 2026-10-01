# Eval

The dataset and harness for measuring `threepass`. The full plan is in [docs/eval-design.md](../docs/eval-design.md).

**Status:** the harness is built, with 5 seed cases that prove the pipeline. No eval has been run against the real API yet, so there are no results. The full 40-case dataset and the first labeled results come in roadmap milestone M7.

```
evals/
  cases/<id>/          case.yml (metadata + ground truth), diff.patch, context/
  configs/             independent.yml, chained.yml, single.yml, single_sampled.yml
  labels/              human labels for findings that didn't match a known defect
  results/             one directory per run: records.json, summary.json, summary.md, misses.md
```

## Run it

```bash
bundle exec rake eval:validate                       # check every case
bundle exec rake "eval:run[independent]"             # prints the spending bound and stops
CONFIRM=yes bundle exec rake "eval:run[independent]" # real run; needs ANTHROPIC_API_KEY
bundle exec rake eval:report                         # rescore with current labels, update the README table
```

Each config runs every case 3 times. A run costs at most cases × 3 × `max_cost_usd`; the task prints that bound before asking for `CONFIRM=yes`.

To exercise the pipeline without an API key, replay fixture responses. The output goes to `tmp/eval-fake/` and never reaches the README:

```bash
EVAL_FAKE=test/fixtures/eval_fake bundle exec rake "eval:run[independent]"
EVAL_RESULTS=tmp/eval-fake/results EVAL_LABELS=tmp/eval-fake/labels bundle exec rake eval:report
```

## Label

After a real run, open `evals/labels/<run-id>.yml` and set each finding's `label`:

| Label | Meaning |
|---|---|
| `real` | A real problem that isn't in the ground truth |
| `false_positive` | Wrong |
| `nitpick` | True, but not worth a comment |
| `unclear` | Can't tell |

Labels carry over to later runs that report the same finding (same case, file, lines and title). Precision stays hidden until at most 5% of findings are unlabeled. Then fill in `misses.md` in the run's results directory with one line per missed defect saying why it was missed.

## Add a case

1. Make `evals/cases/<language>-<kind>-<short-name>/` (any id works; it must match the directory name).
2. `diff.patch`: the PR's unified diff (`gh pr diff N -R owner/repo > diff.patch`).
3. `context/`: the head version of every changed file, at the same paths (fetch them at the PR's merge or head commit).
4. `case.yml`: follow the format in [eval design: case format](../docs/eval-design.md#case-format). Record the license, the PR, the commits and the merge date. Give each defect's lines in the **new** version of the file.
5. Run `bundle exec rake eval:validate`.

Only MIT, Apache-2.0 or BSD-licensed code, with provenance in `case.yml`. Never employer or proprietary code. For a real case, confirm the trace from fix to introducing PR by reading both diffs. For a planted case, say in `notes` exactly what was changed.
