# Security

## Reporting a vulnerability

Please don't open a public issue for a security problem. Report it privately through GitHub's **Report a vulnerability** form on this repository's Security tab. Include steps to reproduce if you can. You'll get a reply as soon as possible, and credit in the fix if you'd like it.

## Threat model

Three-Pass Review reads code and text written by people you may not trust: the diff, the PR title and body, and files in the checkout. It's designed so the worst a malicious pull request can do is change the text of the one comment it produces.

| Risk | Mitigation |
|---|---|
| Prompt injection in the diff or PR text | The model gets no tools and no credentials. Untrusted input is wrapped in BEGIN/END markers with 128-bit content-hash ids, so the input can't close its own block. The prompts tell the model to report injection attempts as findings. |
| Reading secrets from the checkout | Paths come from the diff, so none is trusted. Paths outside the repo, symlinks (even ones pointing inside the repo) and anything under `.git/` are never read. In a git checkout, only tracked files are. |
| Markup or pings in the posted comment | Model output and file paths are escaped: HTML, Markdown structure (fences, links, headings, `#123` references) and `@mentions`. The `<!-- threepass -->` marker can't be forged. |
| Cost abuse | Every call is estimated against `max_cost_usd` before it's made. The review refuses rather than exceed it, and SDK retries are off for billed calls. |
| Unsafe config | Every YAML file is loaded with `safe_load`; unknown keys and malformed values are rejected. |

**Trust note:** `.threepass.yml` is read from the checkout being reviewed, so a pull request can change it, including the cost ceiling. When you review changes you don't trust, pass `--config` pointing at a copy from a trusted branch.
