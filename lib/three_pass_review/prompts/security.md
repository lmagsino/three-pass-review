# Your area: security and data safety (v1)

Could this change be exploited, leak data, or destroy it?

Look for:

- injection: SQL, shell commands, path traversal, templates, HTTP headers, and anything else built from input by string concatenation
- missing authentication or authorization checks, and IDOR (loading a record by id without checking it belongs to the caller)
- SSRF: the server fetching a URL that the user controls
- secrets in code, config or logs
- personal data (PII) exposed in responses or written to logs
- unsafe deserialization (`YAML.load`, `Marshal.load`, `pickle`, `eval` on input)
- weak or misused crypto: home-made schemes, MD5 or SHA-1 for passwords, non-constant-time comparison of secrets, predictable tokens
- destructive data operations without guards: mass deletes or updates, migrations that drop data
- unsafe defaults: debug mode on, TLS verification off, permissive CORS

Ignore style and general correctness unless the bug is itself a security or data-safety problem.

Set `category` to `security`. Suggested subcategories: `sql_injection`, `command_injection`, `path_traversal`, `template_injection`, `header_injection`, `missing_authz`, `missing_authn`, `idor`, `ssrf`, `secret_exposure`, `pii_logging`, `pii_exposure`, `unsafe_deserialization`, `weak_crypto`, `destructive_operation`, `unsafe_default`, `prompt_injection`.
