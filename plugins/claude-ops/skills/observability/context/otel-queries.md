# OTEL store queries — DuckDB and Aspire

Init file: [../otel/cc-otel.sql](../otel/cc-otel.sql). Read routing: [read-routing.md](read-routing.md).

## DuckDB (default for agents)

```bash
duckdb -init ${CLAUDE_PLUGIN_ROOT}/skills/observability/otel/cc-otel.sql -c "SELECT count(*) FROM cc_logs;"
duckdb -init ${CLAUDE_PLUGIN_ROOT}/skills/observability/otel/cc-otel.sql -c "SELECT count(*) FROM cc_spans;"
```

### Views

| View / macro | Source file | Use |
|---|---|---|
| `cc_logs` | `cc-logs.json` | Events (tool_result, tool_decision, api_request, hooks, …) |
| `cc_metrics` | `cc-metrics.json` | token.usage, cost.usage, … |
| `cc_spans` | `cc-traces.json` | One row per span |
| `cc_traces` | aggregate over `cc_spans` | One row per trace_id |
| `cc_logs_cold()` | `cold/cc-logs-*.parquet` | Aged structure logs |
| `cc_metrics_cold()` | `cold/cc-metrics-*.parquet` | Aged metrics |
| `cc_spans_cold()` | `cold/cc-traces-*.parquet` | Aged spans |

Hot + cold union pattern:

```sql
SELECT event_name, count(*) AS n FROM (
  SELECT event_name FROM cc_logs
  UNION ALL
  SELECT event_name FROM cc_logs_cold()
) GROUP BY 1 ORDER BY n DESC;
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

-- cache health by model over the requested scope — the grain the report's Cache health section
-- renders. Consume the scope workflow's cutoff (data-sources.md derives SINCE_ISO per scope;
-- `all` maps to epoch so the predicate still holds). For `session` scope, replace the cutoff
-- line with:  AND session_id = '<session_id>'  (the workflow requires the session filter there).
SELECT model,
       sum(value) FILTER (WHERE attr_type = 'cacheRead')::BIGINT     AS cache_read,
       sum(value) FILTER (WHERE attr_type = 'cacheCreation')::BIGINT AS cache_creation
FROM cc_metrics
WHERE metric_name = 'claude_code.token.usage'
  AND event_time >= TIMESTAMP '<SINCE_ISO>'
GROUP BY 1 ORDER BY cache_creation DESC;
```

Hot-tier only, deliberately: the `cc_*_cold()` macros raise `IO Error: No files found that match
the pattern …` when the cold tier holds no parquet yet, so the union pattern above is for stores
that have aged, not a safe default. Add the cold half only after confirming `cold/` is populated.

### Tool decisions (`claude_code.tool_decision`)

Event `event_name='tool_decision'` in `cc_logs` / `cc_logs_cold()`. Promoted columns:
`decision`, `source`, `tool_name`, `tool_use_id`, `session_id`, `prompt_id`,
`trace_id`, `span_id`.

**Column mapping:** Claude Code's `tool_decision` event emits the deciding-mechanism
attribute as `source` (see monitoring docs). `tool_result` events use `decision_source` for
the same semantics; `cc-otel.sql` coalesces both into the `source` column.

**Use when:** "which tool calls were denied?", "why was this tool call blocked?", "how many
permission denials this session?"

**Do not:** search session transcripts or hook-events.jsonl — those surfaces do not carry
permission outcomes.

**Attribution caveat:** `source='config'` lumps settings, allow/deny rules, managed
policy, CLI tool lists, permission mode, session grants, and inherently-safe-tool logic.
Counts of `reject`+`config` are an upper bound on config-driven denials, not per-rule
attribution.

```sql
-- rejected tool calls in window (upper bound on config-driven denials)
SELECT event_time, tool_name, tool_use_id, decision, source, session_id
FROM cc_logs
WHERE event_name = 'tool_decision'
  AND decision = 'reject'
  AND event_time >= TIMESTAMP '<SINCE_ISO>'
ORDER BY event_time DESC
LIMIT 50;

-- reject rate by tool and source (rate, not raw volume — high-volume tools can reject more
-- calls yet reject a smaller share)
SELECT tool_name, source,
       count(*) FILTER (WHERE decision = 'reject') AS rejects,
       count(*) AS total,
       count(*) FILTER (WHERE decision = 'reject')::DOUBLE
         / NULLIF(count(*), 0) AS reject_rate
FROM cc_logs
WHERE event_name = 'tool_decision'
  AND event_time >= TIMESTAMP '<SINCE_ISO>'
GROUP BY 1, 2
ORDER BY reject_rate DESC, rejects DESC;

-- config-driven denials for a session (join by tool_use_id to trace spans if needed)
SELECT event_time, tool_name, tool_use_id, source
FROM cc_logs
WHERE event_name = 'tool_decision'
  AND session_id = '<session_id>'
  AND decision = 'reject'
  AND source = 'config'
ORDER BY event_time;
```

For multi-week history, union `cc_logs_cold()` per the hot+cold pattern above.

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
