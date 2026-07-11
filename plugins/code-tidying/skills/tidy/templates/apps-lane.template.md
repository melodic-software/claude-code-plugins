# Lane: <apps-lane-name>

TEMPLATE — copy into `.claude/tidy-lanes/<lane-name>.md` and replace every `<placeholder>`.

User-facing applications and their tests. Higher churn than library code, so drift accumulates fastest here — but public HTTP/UI surfaces make more of the candidates behavioral. Classify carefully.

## Scope

```text
<apps-root>/<app-name>/**
<apps-root>/<app-name>.Tests/**
```

## Watch-for patterns

- **Beck #1 — Guard Clauses** — early returns in request handlers and command handlers
- **Beck #2 — Dead Code** — unused endpoints' helpers, orphaned DTO mappers, stale feature-flag branches
- **Beck #5 / #6 — Reading / Cohesion Order** — handler files where the entry point is buried below its helpers
- **Beck #8 / #9 — Explaining Variables / Constants** — request-validation expressions, magic status codes
- **Test-name drift** — test names that no longer describe what the test asserts (rename = F-3, safe for test-internal names)

## Lane-specific extra exclusions

Beyond the global HARD/SOFT lists:

- **HTTP route signatures** — endpoint URL, method, request/response DTO shapes: behavioral, never tidy
- **Browser-rendered UI** (`<ui-glob>` e.g. `**/*.razor`, `**/components/**`) — SOFT: CLI verification can't see rendering; defer
- **<auth-wiring-glob>** — identity/auth flows need a real handshake to verify; defer

## Verification commands

```bash
<build-command>
<test-command>
```

## Conventional Commits type

`refactor:`. Example title: `refactor(<app>): extract error-response helper in <area> handlers`.

## Preferred research sources

- <authority-on-your-app-framework>
- <authority-on-your-testing-stack>
