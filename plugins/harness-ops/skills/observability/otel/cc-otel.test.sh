#!/usr/bin/env bash
# Contract tests for cc-otel.sql: promoted attribute columns, the effort read, and the cold
# macros' hot column contract over cold Parquet written before and after a column was added.
# Each duckdb case skips on its own when duckdb is absent (CI installs it in ci.yml test-linux).

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR

FAILED=0
CASE_NUM=0
pass() {
  CASE_NUM=$((CASE_NUM + 1))
  printf 'PASS: [%d] %s\n' "$CASE_NUM" "$1"
}
fail() {
  CASE_NUM=$((CASE_NUM + 1))
  printf 'FAIL: [%d] %s — expected %q got %q\n' "$CASE_NUM" "$1" "$2" "$3" >&2
  FAILED=$((FAILED + 1))
}
skip_case() { printf 'SKIP: %s\n' "$1" >&2; }
assert_eq() { if [[ "$3" == "$2" ]]; then pass "$1"; else fail "$1" "$2" "$3"; fi; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

sql_path() { # path safe to embed in a SQL string (native duckdb.exe cannot read MSYS paths)
  if command -v cygpath >/dev/null 2>&1; then cygpath -m "$1"; else printf '%s\n' "$1"; fi
}
HAS_DUCKDB=false
command -v duckdb >/dev/null 2>&1 && HAS_DUCKDB=true

STORE="$TMP/store"
mkdir -p "$STORE/cold"
INIT="$(sql_path "$SCRIPT_DIR/cc-otel.sql")"
q() { # query with the store's hot views and the cold macros loaded; csv, no header
  CC_OTEL_STORE="$(sql_path "$STORE")" duckdb -csv -noheader -init "$INIT" -c "$1" 2>/dev/null | tr -d '\r'
}

T1=1759400000000000000
attr() { printf ',{"key":"%s","value":{"%s":%s}}' "$1" "$2" "$3"; }

# Metrics: one token data point with effort, one without.
metric_point() { # <effort|-> <value>
  local a
  a="$(attr session.id stringValue '"s-1"')$(attr model stringValue '"m-x"')$(attr type stringValue '"input"')"
  [[ "$1" == - ]] || a+="$(attr effort stringValue "\"$1\"")"
  printf '{"attributes":[%s],"timeUnixNano":"%s","asInt":"%s"}' "${a#,}" "$T1" "$2"
}
printf '{"resourceMetrics":[{"scopeMetrics":[{"metrics":[{"name":"claude_code.token.usage","unit":"tokens","sum":{"dataPoints":[%s,%s],"aggregationTemporality":1}}]}]}]}\n' \
  "$(metric_point high 5)" "$(metric_point - 7)" >"$STORE/cc-metrics.json"

# Logs: an api_request with effort and typed values, a plugin_loaded with a boolean and a
# duplicated key (the first value wins), and an event with a string-array attribute.
log_record() { # <event.name> <attrs fragment>
  local a
  a="$(attr session.id stringValue '"s-1"')$(attr event.name stringValue "\"$1\"")$2"
  printf '{"timeUnixNano":"%s","body":{"stringValue":"claude_code.%s"},"attributes":[%s]}' "$T1" "$1" "${a#,}"
}
printf '{"resourceLogs":[{"scopeLogs":[{"logRecords":[%s,%s,%s]}]}]}\n' \
  "$(log_record api_request "$(attr effort stringValue '"max"')$(attr cost_usd_micros intValue '"1500"')$(attr cost_usd doubleValue 0.0015)")" \
  "$(log_record plugin_loaded "$(attr has_hooks boolValue true)$(attr plugin.name stringValue '"first"')$(attr plugin.name stringValue '"second"')")" \
  "$(log_record user_prompt "$(attr workspace.host_paths arrayValue '{"values":[{"stringValue":"/w1"},{"stringValue":"/w2"}]}')")" \
  >"$STORE/cc-logs.json"

# Spans: an llm_request with effort, and a tool span whose tool.output event carries output.
{
  printf '{"resourceSpans":[{"scopeSpans":[{"spans":[%s,%s]}]}]}\n' \
    "{\"traceId\":\"t1\",\"spanId\":\"a1\",\"name\":\"claude_code.llm_request\",\"startTimeUnixNano\":\"$T1\",\"endTimeUnixNano\":\"$T1\",\"attributes\":[{\"key\":\"session.id\",\"value\":{\"stringValue\":\"s-1\"}}$(attr effort stringValue '"low"')$(attr input_tokens intValue '"12"')]}" \
    "{\"traceId\":\"t1\",\"spanId\":\"a2\",\"name\":\"claude_code.tool\",\"startTimeUnixNano\":\"$T1\",\"endTimeUnixNano\":\"$T1\",\"attributes\":[{\"key\":\"session.id\",\"value\":{\"stringValue\":\"s-1\"}}$(attr file_path stringValue '"/f"')],\"events\":[{\"name\":\"tool.output\",\"timeUnixNano\":\"$T1\",\"attributes\":[{\"key\":\"output\",\"value\":{\"stringValue\":\"OUT\"}}]}]}"
} >"$STORE/cc-traces.json"

# Old cold files carry only the columns each table had before this schema change.
readonly OLD_LOG_COLS="event_time, session_id, event_name, tool_name, hook_name, decision, duration_ms, success, source, prompt_id, tool_use_id, terminal_type, event_sequence, trace_id, span_id, body, log_attributes_raw"
readonly OLD_METRIC_COLS="event_time, metric_name, metric_unit, value, session_id, model, attr_type, terminal_type, metric_attributes_raw"
readonly OLD_SPAN_COLS="span_time, end_time, trace_id, span_id, parent_span_id, span_name, session_id, span_type, tool_name, tool_use_id, prompt_id, model, user_prompt, success, duration_ms, span_attributes_raw"
cold() { sql_path "$STORE/cold/$1"; }
write_old_cold() {
  q "COPY (SELECT $OLD_LOG_COLS FROM cc_logs) TO '$(cold cc-logs-old.parquet)' (FORMAT PARQUET);
     COPY (SELECT $OLD_METRIC_COLS FROM cc_metrics) TO '$(cold cc-metrics-old.parquet)' (FORMAT PARQUET);
     COPY (SELECT $OLD_SPAN_COLS FROM cc_spans) TO '$(cold cc-traces-old.parquet)' (FORMAT PARQUET);" >/dev/null
}

# --- 1. hot reads: effort promoted on metrics, logs and spans; absent effort groups as unset ---
if [[ "$HAS_DUCKDB" == true ]]; then
  assert_eq "metrics group by effort keeps an unset row" "high,5|unset,7" \
    "$(q "SELECT COALESCE(effort, 'unset'), sum(value)::BIGINT FROM cc_metrics GROUP BY 1 ORDER BY 1;" | paste -sd'|')"
  assert_eq "logs effort column" "max" "$(q "SELECT effort FROM cc_logs WHERE event_name = 'api_request';")"
  assert_eq "spans effort column" "low" "$(q "SELECT effort FROM cc_spans WHERE span_name = 'claude_code.llm_request';")"
else
  skip_case "duckdb not found — skipping hot effort reads"
fi

# --- 2. promoted columns are typed ---
if [[ "$HAS_DUCKDB" == true ]]; then
  assert_eq "cost_usd_micros is BIGINT" "1500,BIGINT" "$(q "SELECT cost_usd_micros, typeof(cost_usd_micros) FROM cc_logs WHERE event_name = 'api_request';")"
  assert_eq "cost_usd is DOUBLE" "0.0015,DOUBLE" "$(q "SELECT cost_usd, typeof(cost_usd) FROM cc_logs WHERE event_name = 'api_request';")"
  assert_eq "has_hooks is BOOLEAN" "true,BOOLEAN" "$(q "SELECT has_hooks, typeof(has_hooks) FROM cc_logs WHERE event_name = 'plugin_loaded';")"
  assert_eq "duplicated key: the first value wins" "first" "$(q "SELECT plugin_name FROM cc_logs WHERE event_name = 'plugin_loaded';")"
  assert_eq "string array attribute is VARCHAR[]" "/w2,VARCHAR[]" "$(q "SELECT workspace_host_paths[2], typeof(workspace_host_paths) FROM cc_logs WHERE event_name = 'user_prompt';")"
  assert_eq "spans input_tokens is BIGINT" "12,BIGINT" "$(q "SELECT input_tokens, typeof(input_tokens) FROM cc_spans WHERE span_name = 'claude_code.llm_request';")"
  assert_eq "tool.output event attribute promoted on the tool span" "OUT,/f" "$(q "SELECT output, file_path FROM cc_spans WHERE span_name = 'claude_code.tool';")"
  assert_eq "raw attribute JSON still holds every span attribute" "1" "$(q "SELECT count(*) FROM cc_spans WHERE span_attributes_raw::VARCHAR LIKE '%\"file_path\"%';")"
else
  skip_case "duckdb not found — skipping typed column reads"
fi

# --- 3. each cold stub's DESCRIBE equals the hot projection's ---
if [[ "$HAS_DUCKDB" == true ]]; then
  for pair in logs:logs metrics:metrics spans:spans; do
    t="${pair%%:*}"
    hot="$(q "SELECT column_name || ' ' || column_type FROM (DESCRIBE SELECT * FROM cc_$t);" | paste -sd'|')"
    stub="$(q "SELECT column_name || ' ' || column_type FROM (DESCRIBE SELECT * FROM cc_${t}_cold_stub());" | paste -sd'|')"
    assert_eq "cc_${t}_cold_stub() matches cc_$t names, order and types" "$hot" "$stub"
  done
else
  skip_case "duckdb not found — skipping stub contract"
fi

# --- 4. all-old cold files: positional hot+cold union and a cold-only effort group-by bind ---
if [[ "$HAS_DUCKDB" == true ]]; then
  write_old_cold
  assert_eq "cold-only group by effort over old files reads unset" "unset,12" \
    "$(q "SELECT COALESCE(effort, 'unset'), sum(value)::BIGINT FROM cc_metrics_cold() GROUP BY 1;")"
  assert_eq "positional hot+cold union of every column binds (logs)" "6" \
    "$(q "SELECT count(*) FROM (SELECT * FROM cc_logs UNION ALL SELECT * FROM cc_logs_cold());")"
  assert_eq "positional hot+cold union of every column binds (spans)" "4" \
    "$(q "SELECT count(*) FROM (SELECT * FROM cc_spans UNION ALL SELECT * FROM cc_spans_cold());")"
  assert_eq "hot+cold metrics grouped by effort" "high,5|unset,19" \
    "$(q "SELECT COALESCE(effort, 'unset'), sum(value)::BIGINT FROM (SELECT effort, value FROM cc_metrics UNION ALL SELECT effort, value FROM cc_metrics_cold()) GROUP BY 1 ORDER BY 1;" | paste -sd'|')"
else
  skip_case "duckdb not found — skipping all-old cold reads"
fi

# --- 5. old and new cold files mixed ---
if [[ "$HAS_DUCKDB" == true ]]; then
  q "COPY (SELECT * FROM cc_metrics) TO '$(cold cc-metrics-new.parquet)' (FORMAT PARQUET);
     COPY (SELECT * FROM cc_logs) TO '$(cold cc-logs-new.parquet)' (FORMAT PARQUET);" >/dev/null
  assert_eq "mixed cold metrics keep the new file's effort" "high,5|unset,19" \
    "$(q "SELECT COALESCE(effort, 'unset'), sum(value)::BIGINT FROM cc_metrics_cold() GROUP BY 1 ORDER BY 1;" | paste -sd'|')"
  assert_eq "mixed cold logs read both files" "6" "$(q "SELECT count(*) FROM cc_logs_cold();")"
  assert_eq "mixed cold logs: promoted column NULL only for the old file's rows" "1" \
    "$(q "SELECT count(*) FROM cc_logs_cold() WHERE cost_usd_micros = 1500;")"
  assert_eq "mixed cold columns keep the hot order" \
    "$(q "SELECT column_name FROM (DESCRIBE SELECT * FROM cc_logs);" | paste -sd'|')" \
    "$(q "SELECT column_name FROM (DESCRIBE SELECT * FROM cc_logs_cold());" | paste -sd'|')"
else
  skip_case "duckdb not found — skipping mixed cold reads"
fi

printf '\n%d passed, %d failed\n' "$((CASE_NUM - FAILED))" "$FAILED"
[[ "$FAILED" -eq 0 ]]
