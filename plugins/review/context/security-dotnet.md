# .NET (C#) security checklist

Loaded on demand by this plugin's `security-reviewer` agent when the change set touches .NET code.
The OWASP table and the cross-ecosystem list in the agent body are the floor for every review;
these are the ecosystem-specific additions that floor does not cover.

- **SQL injection**: ORM parameterization, no raw SQL string concatenation
- **XSS**: raw-markup escapes (`MarkupString`, `Html.Raw`), unencoded output
- **Auth patterns**: token validation, OIDC/OAuth flows (PKCE for public clients, state validated, redirect_uri allowlist)
- **Secrets**: no hardcoded connection strings, API keys, or tokens; check config files for non-placeholder values
- **Deserialization**: polymorphic type handling on untrusted input, legacy formatters
- **Path traversal**: user-controlled segments reaching `Path.Combine`
