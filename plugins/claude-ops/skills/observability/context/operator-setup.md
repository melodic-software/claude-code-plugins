# Local Claude Code observability

Index for local Claude Code (CLI) OpenTelemetry capture into a per-developer store, plus the
optional Aspire dashboard live tail. Machine provisioning owns Collector and dashboard
lifecycle; this file provides the **Naming** section and topic dispatch table below — detail
lives in the linked concern docs.

**Agents:** read routing — [`read-routing.md`](read-routing.md). Scope reports — `/observability`.

## Naming

**CC** = Claude Code CLI (the `claude` binary's telemetry). Shorthand in env vars (`CC_OTEL_*`), store
files (`cc-logs.json`, `cc-metrics.json`, `cc-traces.json`), DuckDB views (`cc_logs`, `cc_metrics`,
`cc_spans`), and hook scripts (`cc-telemetry-ensure.sh`). Docker stack labels use the full slug
`claude-code-observability` (no `cc` in label values). **Not** your application's own OTEL or
Aspire app-host traces.

## Pipeline (summary)

Claude Code → OTLP `http://127.0.0.1:4318` → OTel Collector → fan-out:

- file exporter → `.claude/observability/otel/{cc-logs,cc-metrics,cc-traces}.json` (persistent
  store, gitignored, **`append: true`** so a Collector restart appends rather than truncating;
  DuckDB `read_json_auto` queries via [`../otel/cc-otel.sql`](../otel/cc-otel.sql))
- `otlp_grpc/cc_dashboard` → Aspire standalone dashboard (**all three signals** — optional live UI;
  in-memory, bounded by the dashboard's built-in telemetry caps; restart resets it)

The machine-owned receiver/exporter configuration is
[`common/otel-collector.yaml`](https://github.com/melodic-software/provisioning/blob/main/common/otel-collector.yaml),
and the dashboard stack is
[`common/local-otel-dashboards.compose.yaml`](https://github.com/melodic-software/provisioning/blob/main/common/local-otel-dashboards.compose.yaml).

## Detail (by concern)

| Topic | Doc |
| --- | --- |
| Always-on Collector service + optional Aspire dashboard ownership | [`operator-setup-collector-daemon.md`](operator-setup-collector-daemon.md) |
| Hot/cold retention, prune script, scheduled prune task | [`operator-setup-retention.md`](operator-setup-retention.md) |
| Emission tiers, content-capture keys, privacy, revert to structure-only | [`operator-setup-emission-privacy.md`](operator-setup-emission-privacy.md) |
| DuckDB queries, Aspire live API | [`otel-queries.md`](otel-queries.md) |
