---
applyTo: "src/auth/**,src/payments/**,db/migrations/**,infra/**"
---

These paths are core and sensitive. Changes here always get a deep human review, so point the reviewer at what matters most.

When reviewing these files, also check:

- **Access control.** Every new or changed entry point checks who the caller is and what they're allowed to do. No check was removed or moved after the action it guards.
- **Money and state.** Operations that charge, refund or change balances are idempotent and safe to retry. Amounts use integer minor units or a decimal type, never floats. Partial failures leave a consistent state.
- **Migrations.** The migration works with the code that is running now and the code being deployed (expand, then contract). It can be rolled back, or the PR says why not. It won't lock or rewrite a large table during traffic.
- **Infrastructure.** Defaults are safe. No secrets in plain text. Nothing widens network or IAM access beyond what the change needs.
- **Recoverability.** Call out anything a plain revert would not undo: deleted or rewritten data, external side effects, changed persisted formats.
