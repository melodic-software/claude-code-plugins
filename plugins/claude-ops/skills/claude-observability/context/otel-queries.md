# OTEL store queries — DuckDB and Aspire

Init file: [../otel/cc-otel.sql](../otel/cc-otel.sql). Read routing: [read-routing.md](read-routing.md).

## DuckDB (default for agents)

```bash
duckdb -init ${CLAUDE_PLUGIN_ROOT}/skills/claude-observability/otel/cc-otel.sql -c "SELECT count(*) FROM cc_logs;"
duckdb -init ${CLAUDE_PLUGIN_ROOT}/skills/claude-observability/otel/cc-otel.sql -c "SELECT count(*) FROM cc_spans;"
```

### Views

| View / macro | Source file | Use |
|---|---|---|
| `cc_logs` | `cc-logs.json` | Events (tool_result, api_request, hooks, …) |
| `cc_metrics` | `cc-metrics.json` | token.usage, cost.usage, … |
| `cc_spans` | `cc-traces.json` | One row per span |
| `cc_traces` | aggregate over `cc_spans` | One row per trace_id |
| `cc_logs_cold()` | `cold/cc-logs-*.parquet` | Aged structure logs |
| `cc_metrics_cold()` | `cold/cc-metrics-*.parquet` | Aged metrics |
| `cc_spans_cold()` | `cold/cc-traces-*.parquet` | Aged spans |

Hot + cold union pattern:

```sql
SELECT event_name, count(*) FROM cc_logs
UNION ALL
SELECT event_name, count(*) FROM cc_logs_cold()
GROUP BY 1 ORDER BY 2 DESC;
```

### Common queries

```sql
-- events by kind, recent session
SELECT event_name, count(*) AS n FROM cc_logs
WHERE session_id = '<id>' GROUP BY 1 ORDER BY n DESC;

-- span tree for a trace
SELECT span_time, span_name, duration_ms, tool_name, parent_span_id
FROM cc_spans WHERE trace_id = '<trace_id>' ORDER BY span_time;

-- token usage by kind, latest session
WITH latest AS (
  SELECT session_id FROM cc_metrics GROUP BY 1 ORDER BY max(event_time) DESC LIMIT 1)
SELECT attr_type, sum(value)::BIGINT AS tokens
FROM cc_metrics JOIN latest USING (session_id)
WHERE metric_name = 'claude_code.token.usage' GROUP BY 1;
```

Join logs to traces via shared `trace_id` / `span_id` on log rows.

## Aspire (optional live telemetry UI)

All three signals forwarded (in-memory window). Resource: `claude-code`.

```bash
curl -s "http://localhost:18888/api/telemetry/resources"
curl -s "http://localhost:18888/api/telemetry/traces?resource=claude-code"
```

Aspire CLI (same API, flattened JSON):

```bash
aspire otel traces claude-code \
  --dashboard-url http://localhost:18888 \
  --format Json --limit 5 --non-interactive --nologo
```

Always cap output. Prefer DuckDB for historical or aggregate questions.

## CC emission reference

Span names, metrics catalog, content-privacy flags:
[Claude Code monitoring docs](https://code.claude.com/docs/en/monitoring-usage).
