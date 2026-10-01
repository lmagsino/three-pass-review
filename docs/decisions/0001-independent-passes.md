# ADR 0001: Independent passes plus a reconciler, not a chain

**Status:** Accepted as the default, pending the eval. The eval can overturn it.

## Context

A multi-pass reviewer can be shaped two ways:

- **Chained:** each pass sees the findings of the passes before it, and refines or adds to them.
- **Independent:** each pass sees only the change, does its own job, and a separate reconciler merges the results.

Chaining looks efficient: later passes can skip what's already found. Its risk is **anchoring**. Once a reviewer is shown a list of findings, it tends to judge, extend and rephrase that list instead of looking at the code fresh. A miss in pass 1 then becomes a miss for every later pass, and the passes stop being independent checks.

## Decision

- **Passes run independently, in parallel, on the same frozen input.** No pass sees another's output.
- **A deterministic reconciler merges duplicates, scores agreement and ranks.** Two passes flagging the same lines independently is evidence; one pass agreeing with what it was shown is not.
- **Enforced in code.** The runner builds the input once and freezes it, and a test asserts no request contains another pass's output.

## Consequences

- **Cost.** About three times the input tokens of a single pass, and the same problem can be reported more than once. The reconciler handles duplicates, and the cost ceiling handles cost. Every review reports its cost.
- **Agreement becomes a signal.** Combined confidence rises when separate passes flag the same lines.
- **The comparison is built in.** Chained, single and single-sampled modes are kept in the runner purely so the eval can compare against them.

## How we'll know if this is wrong

The eval runs four configurations on the same dataset ([eval design](../eval-design.md#configurations-compared)):

| Result | Then |
|---|---|
| `independent` beats `chained` on recall, with intervals that don't overlap | The anchoring argument holds. Write it up |
| `single_sampled` is as good as `independent` | The gain is from sampling, not specialization. Simplify to one prompt sampled N times |
| `single` is as good as `independent` at a third of the cost | Three passes aren't worth it. Ship one pass |
| No clear difference anywhere | Say so, keep `independent` for its per-category reporting, and collect more cases |

Whatever happens, publish the result. A negative result, measured honestly, is still a good post.
