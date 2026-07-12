# Operator setup — emission + privacy

Parent: [`operator-setup.md`](operator-setup.md). Retention: [`operator-setup-retention.md`](operator-setup-retention.md).

## Emission profile (`.claude/settings.json` `env`)

CC reads these at session start — `settings.json` `env` drives CC's own telemetry. Two tiers.

### Structure-only baseline (always on)

`CLAUDE_CODE_ENABLE_TELEMETRY`, `OTEL_LOGS_EXPORTER`, `OTEL_METRICS_EXPORTER`,
`OTEL_EXPORTER_OTLP_ENDPOINT`, `OTEL_EXPORTER_OTLP_PROTOCOL`, `OTEL_METRIC_EXPORT_INTERVAL`.
Captures span/event names, durations, counts, and identity attrs (`session.id`,
`user.account_uuid`, and under OAuth `user.email`) — **no** prompt / tool / API-body content.
`session.id` and `user.account_uuid` metric attrs are on by CC default.

### Trace + version keys (committed, structure-level)

Three more keys live in the committed `env` block — they add structure, not content:
`CLAUDE_CODE_ENHANCED_TELEMETRY_BETA=1` + `OTEL_TRACES_EXPORTER=otlp` (span tracing — required
for traces) and `OTEL_METRICS_INCLUDE_VERSION=true` (`app.version` metric attribute).

### Content-capture keys (contributor-local opt-in)

The four content keys are **contributor-scoped** — they put real conversation content in the
store (CWE-532/359) — so they live in each developer's gitignored `.claude/settings.local.json`
`env`, never the committed `settings.json`:

| Key | Effect |
|---|---|
| `OTEL_LOG_USER_PROMPTS=1` | prompt text in events/spans (else `<REDACTED>`) |
| `OTEL_LOG_TOOL_DETAILS=1` | tool input details in spans |
| `OTEL_LOG_TOOL_CONTENT=1` | tool content in spans |
| `OTEL_LOG_RAW_API_BODIES=1` | raw API request/response bodies (inline, truncated at 60 KB) |

Exact flag names and accepted values: [Claude Code monitoring
docs](https://code.claude.com/docs/en/monitoring-usage).

- `OTEL_LOG_RAW_API_BODIES=1` is inline mode — bodies truncated at 60 KB. For untruncated
  bodies use `file:<dir>`, which writes a **separate** directory that must ALSO be gitignored.
- **Traces** persist to `cc-traces.json` (query via `cc_spans` / `cc_traces`) and optionally
  fan out to the Aspire dashboard for live UI. Historical queries:
  [`otel-queries.md`](otel-queries.md).

## Privacy consequence (read before leaving full capture ON)

With the content-capture keys active, the persistent store (`.claude/observability/otel/cc-logs.json`)
holds **real prompt text, tool input/output, and raw API bodies** — full conversation history,
which can include secrets pasted into prompts. Barriers:

- **Gitignored** — the store is under `.claude/observability/` (never committed). Verify:
  `git check-ignore .claude/observability/otel/`.
- **Per-developer-local** — each contributor's store is their own machine only; nothing shared.
- **NOT secret-scanned** — the `secret-pattern-detection` hook does not scan Collector-written
  files; gitignore + per-dev + retention is the whole barrier.
- **Retention** — `/claude-observability clean` (or `otel/prune-otel-store.sh` in this skill)
  prunes the store to `CC_OTEL_RETENTION_DAYS` (default 7; `api_*_body` records age out at
  `CC_OTEL_BODY_RETENTION_DAYS`, default 2), bounding the full-capture exposure window. The
  cold Parquet tier keeps structure only — no `api_*_body` rows, prompts scrubbed unless
  `CC_OTEL_COLD_KEEP_USER_PROMPTS=1` — so content exposure stays bounded by the hot windows.
  See [operator-setup-retention.md](operator-setup-retention.md) "Pruning the store (retention) — two tiers".

## Reverting to structure-only

Delete the four content-capture keys (the table above) from your `.claude/settings.local.json`
`env`, or set them to `0`. The committed baseline (structure + traces) keeps emitting — the
committed `settings.json` carries no content keys to remove.

Changes take effect on the **next** CC session (env is read at session start).
