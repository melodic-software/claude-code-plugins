# Security review mode

Delegates to this plugin's `security-reviewer` agent for a cross-ecosystem security audit. Use when changes touch authentication, authorization, data handling, API endpoints, or any code processing user input.

**Output schema:** the agent produces P1–P5 findings (severity, location, risk, fix, confidence). When rolling up into this skill's summary, fold P1/P2 → CRITICAL, P3 → IMPORTANT, P4/P5 → SUGGESTION (per `${CLAUDE_PLUGIN_ROOT}/context/severity.md`).

## When to use

- Modifying authentication or authorization logic
- Adding or changing API endpoints
- Processing user input (HTTP requests, tool parameters, file paths)
- Adding new dependencies (known CVEs)
- Handling secrets, tokens, or connection strings
- Modifying CORS policies or error responses
- Any code processing PII

## How to invoke

Launch the `security-reviewer` agent with:

- **Scope** — the changed files and their security context
- **Focus** — specific concerns (e.g. "this handles user-uploaded file paths")
- **Input** — the review diff base (SKILL.md "Shared inputs") or specific file paths

The agent covers per-ecosystem injection/XSS/deserialization/path-traversal checks, the OWASP Top 10, security headers, and auth-specific checks (see the agent definition for the full baseline).

## After the review

- **CRITICAL findings** — fix immediately, no exceptions
- **Input validation gaps** — add validation at the boundary (entry point), not deep in the call stack
- **Secrets exposure** — rotate exposed secrets first, then fix the code
- **Dependency CVEs** — run the ecosystem's audit command; update or pin
- **Static-analysis backstop** — when the project runs a security scanner (CodeQL or similar), consider triggering it for urgent checks
