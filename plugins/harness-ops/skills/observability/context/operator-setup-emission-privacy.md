# Operator setup: emission + privacy

Parent: [`operator-setup.md`](operator-setup.md). Retention: [`operator-setup-retention.md`](operator-setup-retention.md).

## Emission profile (where each key lives)

CC reads these at session start. Two homes: each developer's **user scope** (user settings
`~/.claude/settings.json` `env`, or the shell) for every key that turns telemetry on, picks its
destination, or captures content, and the committed project `.claude/settings.json` `env` for
structure-only keys. Health check: if startup or `/status` reports ignored variables, move them
to user scope.

- **Pointer**: when deciding whether a telemetry key may sit in a project or local settings
  file, fetch
  [settings reference: variables Claude Code ignores in env](https://code.claude.com/docs/en/settings-reference#variables-claude-code-ignores-in-env)
  and [monitoring: administrator configuration](https://code.claude.com/docs/en/monitoring-usage#administrator-configuration)
  live.
- **As of**: 2026-10-10
- **Recheck trigger**: that settings-reference section changes its list of ignored telemetry
  variables or its version floor.

### Structure-only baseline (user scope, always on)

`CLAUDE_CODE_ENABLE_TELEMETRY`, `OTEL_LOGS_EXPORTER`, `OTEL_METRICS_EXPORTER`,
`OTEL_EXPORTER_OTLP_ENDPOINT`, `OTEL_EXPORTER_OTLP_PROTOCOL` in user settings or the shell.
Captures span/event names, durations, counts, and identity attrs (`session.id`,
`user.account_uuid`, and under OAuth `user.email`), with **no** prompt / tool / API-body content.
`session.id` and `user.account_uuid` metric attrs are on by CC default.

### Traces (user scope)

`CLAUDE_CODE_ENHANCED_TELEMETRY_BETA=1` + `OTEL_TRACES_EXPORTER=otlp` (span tracing, required
for traces) go beside the baseline in user scope. They add structure, not content.

### Structure-only keys (committed project `env`)

`OTEL_METRIC_EXPORT_INTERVAL`, `OTEL_METRICS_INCLUDE_VERSION=true` (`app.version` metric
attribute) and `OTEL_METRICS_INCLUDE_REPOSITORY=true` stay in the committed `env` block. We set
the repository key so the store's `vcs_repository_*`, `vcs_owner_name` and `vcs_provider_name`
columns can fill. That these keys still apply from project settings is our
reading: none of them is on the ignored list.

- **Pointer**: when checking which attributes the repository key adds, fetch
  [monitoring: repository attributes](https://code.claude.com/docs/en/monitoring-usage#repository-attributes)
  live.
- **As of**: 2026-10-10
- **Recheck trigger**: the ignored-variables list gains an interval or `OTEL_METRICS_INCLUDE_*`
  key, or the repository-attributes section changes.

### Content-capture keys (contributor opt-in, user scope)

The four content keys are **contributor-scoped**. They put real conversation content in the
store (CWE-532/359), so each developer who wants them sets them in user scope, never in a
committed file. To capture one project only, export them in the shell that launches it.

| Key | Effect |
|---|---|
| `OTEL_LOG_USER_PROMPTS=1` | prompt text in events/spans (else `<REDACTED>`) |
| `OTEL_LOG_TOOL_DETAILS=1` | see the pointer below; needed in user scope for the `vcs_ref_head_*` columns |
| `OTEL_LOG_TOOL_CONTENT=1` | tool content in spans |
| `OTEL_LOG_RAW_API_BODIES=1` | raw API request/response bodies (inline, truncated at 60 KB) |

Exact flag names and accepted values: [Claude Code monitoring
docs](https://code.claude.com/docs/en/monitoring-usage).

- **Pointer**: when checking what `OTEL_LOG_TOOL_DETAILS` adds, fetch
  [monitoring: cost counter](https://code.claude.com/docs/en/monitoring-usage#cost-counter) and
  [monitoring: tool result event](https://code.claude.com/docs/en/monitoring-usage#tool-result-event)
  live.
- **As of**: 2026-10-10
- **Recheck trigger**: either section changes what the flag adds.

- `OTEL_LOG_RAW_API_BODIES=1` is inline mode, with bodies truncated at 60 KB. For untruncated
  bodies use `file:<dir>`, which writes a **separate** directory that must ALSO be gitignored.
- **Traces** persist to `cc-traces.json` (query via `cc_spans` / `cc_traces`) and optionally
  fan out to the Aspire dashboard for live UI. Historical queries:
  [`otel-queries.md`](otel-queries.md).

## Privacy consequence (read before leaving full capture ON)

With the content-capture keys active, the persistent store (`.claude/observability/otel/cc-logs.json`)
holds **real prompt text, tool input/output, and raw API bodies**, the full conversation history,
which can include secrets pasted into prompts. Barriers:

- **Gitignored**: the store is under `.claude/observability/` (never committed). Verify:
  `git check-ignore .claude/observability/otel/`.
- **Per-developer-local**: each contributor's store is their own machine only; nothing shared.
- **NOT secret-scanned**: the `secret-pattern-detection` hook does not scan Collector-written
  files; gitignore + per-dev + retention is the whole barrier.
- **Retention**: `/harness-ops:observability clean` (or `otel/prune-otel-store.sh` in this skill)
  prunes the store to `CC_OTEL_RETENTION_DAYS` (default 7; `api_*_body` records age out at
  `CC_OTEL_BODY_RETENTION_DAYS`, default 2), bounding the full-capture exposure window. The
  cold Parquet tier keeps structure only, with no `api_*_body` rows and prompts scrubbed unless
  `CC_OTEL_COLD_KEEP_USER_PROMPTS=1`, so content exposure stays bounded by the hot windows.
  See [operator-setup-retention.md](operator-setup-retention.md) "Pruning the store (retention): two tiers".

## Reverting to structure-only

Delete the four content-capture keys (the table above) from your user settings `env` or shell
profile. To turn one off for a single project, check the ignored-variables pointer above for
which off values a project or local settings file honors. The user-scope baseline and traces keep emitting, and the committed `settings.json` carries no
content keys to remove.

Changes take effect on the **next** CC session (env is read at session start).
