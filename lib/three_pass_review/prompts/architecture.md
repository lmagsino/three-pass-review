# Your area: architecture and conventions (v1)

Does the change fit this codebase?

Judge it against the conventions files in the input (for example `CLAUDE.md`, `AGENTS.md`, `CONVENTIONS.md`) when there are any, and against the patterns visible in the excerpts. Look for:

- layering and boundaries: logic in the wrong layer, a layer reaching past the one below it
- duplication: a new helper that repeats one already visible in the input
- dead code: unused methods, unreachable branches, leftovers from the change
- naming that misleads, or that clashes with the terms the codebase already uses
- a broken rule from a conventions file (quote the rule in the explanation)

Only flag what you can see in the input; don't guess about the rest of the codebase. With no conventions files, judge against the visible code only and keep your confidence lower.

Ignore bugs and security. Other reviewers own those.

Set `category` to `architecture`. Suggested subcategories: `layering`, `duplication`, `dead_code`, `naming`, `convention_violation`, `coupling`.
