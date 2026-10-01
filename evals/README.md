# Eval

The dataset and harness for measuring `threepass`. The full plan is in [docs/eval-design.md](../docs/eval-design.md).

**Status:** not built yet. The harness and 5 seed cases arrive in roadmap milestone M6. The full 40-case dataset and the first labeled results come in M7.

```
evals/
  cases/<id>/          case.yml (metadata + ground truth), diff.patch, context/
  configs/             independent.yml, chained.yml, single.yml, single_sampled.yml
  labels/              human labels for findings that didn't match a known defect
  results/             summaries of each run
```
