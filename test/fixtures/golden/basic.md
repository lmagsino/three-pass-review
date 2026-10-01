<!-- threepass -->

### threepass: 4 findings (1 high)

| | Finding | Where | Passes | Confidence |
|---|---|---|---|---|
| 🔴 high | User input interpolated into SQL | `app/models/invoice.rb:8` | correctness, security | 0.96 |
| 🟠 medium | Nil customer not handled in total_due | `app/models/invoice.rb:16` | correctness | 0.72 |
| 🟠 medium | Model reads request params directly | `app/models/invoice.rb:7-9` | architecture | 0.70 |
| 🟡 low | SORTABLE allow-list is defined but never used | `app/models/invoice.rb:5` | architecture | 0.66 |

<details><summary>Details</summary>

**1. 🔴 User input interpolated into SQL** `app/models/invoice.rb:8` · security/sql_injection

params[:sort] is interpolated into ORDER BY without allow-listing.

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

<sub>Cost $0.027 (correctness $0.010 · security $0.008 · architecture $0.010) · 5,850 input / 1,530 output tokens · 1 below threshold · model claude-sonnet-5-5 · prompts PROMPTS_VERSION</sub>
