---
bump: minor
---

### Added

- **Observability by default.** `/implementation:implement` reads the new
  `reference/observability.md` before writing or changing code that runs at runtime: structured
  logs with message templates and scopes or child loggers, compile-time or allocation-free logging
  on hot paths, telemetry configured from the environment (the `OTEL_EXPORTER_OTLP_ENDPOINT`
  family) instead of literals, cross-cutting logging and timing in middleware, decorators or
  pipeline behaviors with in-method logs where the method decides something, log levels raised
  only through untracked local config, and caught errors recorded with the exception and the
  operation's fields. Short .NET and JavaScript examples, with pointers to the live docs.
- **Advisory mutation run at completion.** When the `mutation-testing` plugin is enabled, Step 5
  runs `/mutation-testing:audit --persist-findings` on the committed change's diff once the
  affected tests are green, reports the score, survivors and findings path (or the audit's refusal)
  and continues to the review hand-off whatever the score. A run whose tracked source could not be
  restored stops before review. Without the plugin, the handoff says once what it would add.
