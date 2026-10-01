<!-- threepass -->

### Review brief: 4 findings (1 high)

**The change.** Adds sorting to the invoice list: Invoice.sorted orders invoices by a column named in the request. It also subtracts customer credit in total_due and counts an invoice as overdue on its due date.

**Change map** <sub>(computed from the diff)</sub>

| Area | Files | Lines | Flags |
|---|---|---|---|
| `app/models` | 1 | +8 −2 |  |

1 file, +8 −2 lines.

**What changed**

- `app/models`: New Invoice.sorted(params) and a SORTABLE list; total_due now subtracts credit; overdue? now includes the due date.

**Impact**

- **API or contract:** New public class method Invoice.sorted(params).
- **Behavior:** total_due is lower for customers with credit; invoices count as overdue one day earlier.

**Risks**

- The sort column comes straight from the request.
- Invoices without a customer may now fail in total_due.

**Rollback.** A plain revert undoes it: no migration or stored data changes are visible in the diff.

**Tests**

- Covered: none visible in the diff
- Gap: No tests for sorting, credit or the overdue boundary are visible in the diff.

**Where to look first**

1. 🔴 high · `app/models/invoice.rb:8` · User input interpolated into SQL _(correctness, security)_
2. 🟠 medium · `app/models/invoice.rb:16` · Nil customer not handled in total_due _(correctness)_
3. 🟠 medium · `app/models/invoice.rb:7-9` · Model reads request params directly _(architecture)_
4. `app/models/invoice.rb:100` · The overdue boundary changed from &lt; to &lt;=. _(brief)_

**Questions for the author**

- Which columns should be sortable?
- Is counting the due date as overdue intended?

<details><summary>Findings (4)</summary>

| | Finding | Where | Passes | Confidence |
|---|---|---|---|---|
| 🔴 high | User input interpolated into SQL | `app/models/invoice.rb:8` | correctness, security | 0.96 |
| 🟠 medium | Nil customer not handled in total_due | `app/models/invoice.rb:16` | correctness | 0.72 |
| 🟠 medium | Model reads request params directly | `app/models/invoice.rb:7-9` | architecture | 0.70 |
| 🟡 low | SORTABLE allow-list is defined but never used | `app/models/invoice.rb:5` | architecture | 0.66 |

**1. 🔴 User input interpolated into SQL** `app/models/invoice.rb:8` · security/sql_injection

params\[:sort\] is interpolated into ORDER BY without allow-listing.

```
order("#{params[:sort]} DESC")
```

**Suggested fix:** Allow-list sort columns with SORTABLE.

---

**2. 🟠 Nil customer not handled in total_due** `app/models/invoice.rb:16` · correctness/nil_handling

Invoices without a customer raise NoMethodError when total_due is called.

```
line_items.sum(&:amount) - customer.credit
```

**Suggested fix:** Use customer&amp;.credit.to_i.

---

**3. 🟠 Model reads request params directly** `app/models/invoice.rb:7-9` · architecture/convention_violation

CONVENTIONS.md says models never read params; controllers allow-list them.

```
def self.sorted(params)
```

**Suggested fix:** Take a column name argument and allow-list it in the controller.

---

**4. 🟡 SORTABLE allow-list is defined but never used** `app/models/invoice.rb:5` · architecture/dead_code

The constant suggests an allow-list, but sorted ignores it.

```
SORTABLE = %w[created_at total].freeze
```

**Suggested fix:** Use it in sorted or remove it.

</details>

<details><summary>Sign-off draft</summary>

Copy it into your approval and replace each <…>.

```
Deep review
- Verified: <how you checked the tests> (brief: no tests visible)
- Constraints: <the invariants you checked>
- Rollback: A plain revert undoes it: no migration or stored data changes are visible in the diff.
- Asked: Which columns should be sortable? -> <answer>
- Asked: Is counting the due date as overdue intended? -> <answer>
- Follow-ups: <issues filed, or none>
```

</details>

<sub>Cost $0.038 (correctness $0.010 · security $0.008 · architecture $0.010 · brief $0.011) · 7,950 input / 2,180 output tokens · 1 below threshold · model claude-sonnet-5-5 · prompts PROMPTS_VERSION</sub>
