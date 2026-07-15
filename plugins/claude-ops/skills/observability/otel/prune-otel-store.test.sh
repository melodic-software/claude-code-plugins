#!/usr/bin/env bash
# Black-box contract tests for prune-otel-store.sh.
# Drives the script as a subprocess against a FIXTURE store with the Collector stop/running/
# verify/restart/compact hooks stubbed (CC_OTEL_*_CMD / CC_OTEL_START_SCRIPT seams) — it never
# touches the real machine Collector or the real store.
#
# Two fixture grades:
#   - log_line/metric_line: minimal lines for trim-mechanics cases (lock, verify, dry-run, …).
#     These run with the compact seam stubbed (COMPACT_STUB) so they stay hermetic — no duckdb.
#   - real_log_line/real_metric_line: realistic OTLP/JSON shapes (resource+scope envelope,
#     typed attributes, traceId/spanId) for the cold-compaction cases, which run the REAL
#     duckdb COPY path and assert on cold Parquet CONTENT (state-based). Those cases gate on
#     `command -v duckdb` -> skip_case (CI installs duckdb; see shell-lint.yml bash-tests).

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR
readonly SCRIPT="$SCRIPT_DIR/prune-otel-store.sh"

FAILED=0
CASE_NUM=0
# Inline test helpers — self-contained, no external test lib (ships with the plugin).
FAILED=0
CASE_NUM=0
pass() { CASE_NUM=$((CASE_NUM + 1)); printf 'PASS: [%d] %s\n' "$CASE_NUM" "$1"; }
fail() {
  CASE_NUM=$((CASE_NUM + 1))
  printf 'FAIL: [%d] %s — expected %q got %q\n' "$CASE_NUM" "$1" "$2" "$3" >&2
  FAILED=$((FAILED + 1))
}
skip_case() { printf 'SKIP: %s\n' "$1" >&2; }
assert_eq() { if [[ "$3" == "$2" ]]; then pass "$1"; else fail "$1" "$2" "$3"; fi; }
assert_exit() { if [[ "$3" == "$2" ]]; then pass "$1"; else fail "$1" "exit $2" "exit $3"; fi; }
assert_contains() { if [[ "$2" == *"$3"* ]]; then pass "$1"; else fail "$1" "contains: $3" "$2"; fi; }
assert_not_contains() { if [[ "$2" != *"$3"* ]]; then pass "$1"; else fail "$1" "absent: $3" "$2"; fi; }
assert_file_exists() { if [[ -f "$2" ]]; then pass "$1"; else fail "$1" "file exists: $2" "absent"; fi; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# Hermeticity: the developer's environment must not leak retention knobs into the cases
# (RETENTION_DAYS guard would trip every run if RETENTION_DAYS were exported machine-wide).
unset RETENTION_DAYS CC_OTEL_RETENTION_DAYS CC_OTEL_BODY_RETENTION_DAYS CC_OTEL_COLD_KEEP_USER_PROMPTS

# Stubs: stop hook + restart script touch markers so invocation is assertable; the compact
# stub mimics a successful duckdb COPY by creating the cold temp it is handed ($2).
STOP_STUB="$TMP/stop-stub.sh"
START_STUB="$TMP/start-stub.sh"
COMPACT_STUB="$TMP/compact-stub.sh"
printf '#!/usr/bin/env bash\ntouch "%s/stopped.marker"\n' "$TMP" >"$STOP_STUB"
printf '#!/usr/bin/env bash\ntouch "%s/restarted.marker"\n' "$TMP" >"$START_STUB"
# shellcheck disable=SC2016  # literal $2 must reach the stub script unexpanded
printf '#!/usr/bin/env bash\n: >"$2"\n' >"$COMPACT_STUB"
chmod +x "$STOP_STUB" "$START_STUB" "$COMPACT_STUB"

NOW="$EPOCHSECONDS"
mk_nano() { printf '%s000000000' "$1"; } # 10-digit seconds -> 19-digit nanoseconds
RECENT="$(mk_nano "$((NOW - 3600))")"    # 1h ago  -> kept  (within default 2d body window)
MID="$(mk_nano "$((NOW - 4 * 86400))")"  # 4d ago  -> inside structure window (7d), past body window (2d)
OLD="$(mk_nano "$((NOW - 30 * 86400))")" # 30d ago -> dropped

log_line() { # <timeUnixNano> <observedTimeUnixNano>
  printf '{"resourceLogs":[{"scopeLogs":[{"logRecords":[{"timeUnixNano":"%s","observedTimeUnixNano":"%s","body":{"stringValue":"x"}}]}]}]}\n' "$1" "$2"
}
metric_line() { # <timeUnixNano> <startTimeUnixNano>
  printf '{"resourceMetrics":[{"scopeMetrics":[{"metrics":[{"name":"m","sum":{"dataPoints":[{"timeUnixNano":"%s","startTimeUnixNano":"%s","asInt":"1"}]}}]}]}]}\n' "$1" "$2"
}

# Realistic OTLP/JSON building blocks mirroring real Collector file-exporter output.
# log_record_json emits ONE logRecord object (no envelope) so multi-record batch lines can
# be composed; real_log_batch wraps 1+ comma-joined record objects in the resource/scope
# envelope. <extra> is a (possibly empty) comma-prefixed JSON fragment of extra attributes.
log_record_json() { # <timeUnixNano> <event.name> <body> <extra_attrs_fragment>
  printf '{"timeUnixNano":"%s","observedTimeUnixNano":"%s","body":{"stringValue":"%s"},"attributes":[{"key":"session.id","value":{"stringValue":"sess-1"}},{"key":"event.name","value":{"stringValue":"%s"}},{"key":"event.sequence","value":{"intValue":"7"}},{"key":"prompt.id","value":{"stringValue":"prompt-1"}}%s],"flags":1,"traceId":"63e3a31084d9ef0b979eac79605c0447","spanId":"fdba34d3c48541c2"}' \
    "$1" "$1" "$3" "$2" "$4"
}
real_log_batch() { # <logRecords_json: one or more comma-joined record objects>
  printf '{"resourceLogs":[{"resource":{"attributes":[{"key":"service.name","value":{"stringValue":"claude-code"}}]},"scopeLogs":[{"scope":{"name":"com.anthropic.claude_code.events","version":"2.1.167"},"logRecords":[%s]}]}]}\n' "$1"
}
real_log_line() { # <timeUnixNano> <event.name> <body> <extra_attrs_fragment>
  real_log_batch "$(log_record_json "$@")"
}
real_metric_line() { # <timeUnixNano> <metric_name> <value_fragment e.g. "asInt":"123">
  printf '{"resourceMetrics":[{"resource":{"attributes":[{"key":"service.name","value":{"stringValue":"claude-code"}}]},"scopeMetrics":[{"scope":{"name":"com.anthropic.claude_code","version":"2.1.167"},"metrics":[{"name":"%s","unit":"tokens","sum":{"dataPoints":[{"attributes":[{"key":"session.id","value":{"stringValue":"sess-1"}},{"key":"type","value":{"stringValue":"input"}}],"startTimeUnixNano":"%s","timeUnixNano":"%s",%s}],"aggregationTemporality":1,"isMonotonic":true}}]}]}]}\n' \
    "$2" "$1" "$1" "$3"
}
trace_line() { # <startTimeUnixNano>
  printf '{"resourceSpans":[{"scopeSpans":[{"spans":[{"traceId":"63e3a31084d9ef0b979eac79605c0447","spanId":"fdba34d3c48541c2","name":"claude_code.tool","kind":1,"startTimeUnixNano":"%s","endTimeUnixNano":"%s","attributes":[]}]}]}]}\n' \
    "$1" "$1"
}
real_trace_line() { # <startTimeUnixNano> <span_name> <extra_attrs_fragment>
  printf '{"resourceSpans":[{"resource":{"attributes":[{"key":"service.name","value":{"stringValue":"claude-code"}}]},"scopeSpans":[{"scope":{"name":"com.anthropic.claude_code.tracing","version":"1.0.0"},"spans":[{"traceId":"63e3a31084d9ef0b979eac79605c0447","spanId":"fdba34d3c48541c2","name":"%s","kind":1,"startTimeUnixNano":"%s","endTimeUnixNano":"%s","attributes":[{"key":"session.id","value":{"stringValue":"sess-1"}},{"key":"span.type","value":{"stringValue":"tool"}}%s]}]}]}]}\n' \
    "$2" "$1" "$1" "$3"
}

readonly TOOL_EXTRA=',{"key":"tool_name","value":{"stringValue":"Bash"}},{"key":"tool_use_id","value":{"stringValue":"toolu-1"}},{"key":"duration_ms","value":{"stringValue":"42"}}'
readonly PROMPT_EXTRA=',{"key":"prompt","value":{"stringValue":"SECRET_PROMPT_SENTINEL"}},{"key":"prompt_length","value":{"stringValue":"22"}}'
readonly SPAN_PROMPT_EXTRA=',{"key":"user_prompt","value":{"stringValue":"SECRET_PROMPT_SENTINEL"}}'
readonly API_EXTRA=',{"key":"body","value":{"stringValue":"API_BODY_SENTINEL"}},{"key":"model","value":{"stringValue":"claude-x"}}'
readonly DOUBLE_EXTRA=',{"key":"cost_usd","value":{"doubleValue":123.456}}'
# The body-class classifier text INSIDE a JSON string value: every quote arrives escaped
# (\"), so the unescaped anchored marker the router matches cannot occur. A structure line
# carrying this content must NOT be classified as a body line.
readonly FOOTGUN_EXTRA=',{"key":"note","value":{"stringValue":"saw {\"key\":\"event.name\",\"value\":{\"stringValue\":\"api_request_body\"}} in content"}}'

# Each case builds its own fixture store dir and runs prune with all live-side hooks stubbed.
new_store() {
  local d="$TMP/store-$1"
  mkdir -p "$d"
  printf '%s' "$d"
}
run_prune() { # <store_dir> <args...>; running-check=false (gone immediately), verify=true, compact stubbed
  CC_OTEL_STORE="$1" \
    CC_OTEL_STOP_CMD="$STOP_STUB" \
    CC_OTEL_RUNNING_CMD=false \
    CC_OTEL_VERIFY_CMD=true \
    CC_OTEL_COMPACT_CMD="$COMPACT_STUB" \
    CC_OTEL_START_SCRIPT="$START_STUB" \
    bash "$SCRIPT" "${@:2}" 2>&1
}
run_prune_real() { # <store_dir> <args...>; machine-protection stubs only — REAL duckdb verify + compaction
  CC_OTEL_STORE="$1" \
    CC_OTEL_STOP_CMD="$STOP_STUB" \
    CC_OTEL_RUNNING_CMD=false \
    CC_OTEL_START_SCRIPT="$START_STUB" \
    bash "$SCRIPT" "${@:2}" 2>&1
}

dq() { # one-shot duckdb query, csv, no header
  duckdb -csv -noheader -c "$1" 2>/dev/null | tr -d '\r'
}
dq_macro() { # dq through cc-otel.sql so the cc_logs_from/cc_metrics_from macros are loaded.
  # CC_OTEL_STORE points at a dir with no store files: hot-view binds fail fast, `.bail off`
  # carries the load through (same pattern as the script's own compaction invocation).
  CC_OTEL_STORE="$TMP/no-store" duckdb -csv -noheader \
    -init "$(sql_path "$SCRIPT_DIR/cc-otel.sql")" -c "$1" 2>/dev/null | tr -d '\r'
}
sql_path() { # path safe to embed in a SQL string (native duckdb.exe cannot read MSYS paths)
  if command -v cygpath >/dev/null 2>&1; then cygpath -m "$1"; else printf '%s\n' "$1"; fi
}
HAS_DUCKDB=false
command -v duckdb >/dev/null 2>&1 && HAS_DUCKDB=true

# --- 1. --help: exit 0, prints usage ---
out="$(bash "$SCRIPT" --help 2>&1)"
rc=$?
assert_eq "--help exits 0" "0" "$rc"
assert_contains "--help prints Usage" "$out" "Usage:"

# --- 2. unknown arg: exit 2 ---
out="$(bash "$SCRIPT" --bogus 2>&1)"
rc=$?
assert_eq "unknown arg exits 2" "2" "$rc"
assert_contains "unknown arg reported" "$out" "unknown argument"

# --- 3. --dry-run: reports counts, mutates nothing, creates no cold/ ---
S="$(new_store dry)"
{
  log_line "$RECENT" "$RECENT"
  log_line "$OLD" "$OLD"
} >"$S/cc-logs.json"
before="$(wc -l <"$S/cc-logs.json" | tr -d ' \r')"
out="$(run_prune "$S" --dry-run)"
rc=$?
assert_eq "--dry-run exits 0" "0" "$rc"
assert_contains "--dry-run reports cc-logs counts" "$out" "cc-logs.json: kept=1 dropped=1 total=2"
assert_contains "--dry-run action" "$out" "action=dry-run"
after="$(wc -l <"$S/cc-logs.json" | tr -d ' \r')"
assert_eq "--dry-run leaves file unchanged" "$before" "$after"
assert_not_contains "--dry-run never stops Collector" "$(ls "$TMP")" "stopped.marker"
if [[ -d "$S/cold" ]]; then
  fail "--dry-run creates no cold dir" "absent" "present"
else
  pass "--dry-run creates no cold dir"
fi

# --- 4. footgun: OLD timeUnixNano + RECENT observedTimeUnixNano -> counted DROPPED ---
S="$(new_store footgun-log)"
log_line "$OLD" "$RECENT" >"$S/cc-logs.json"
out="$(run_prune "$S" --dry-run)"
assert_contains "anchored regex keys on timeUnixNano not observedTimeUnixNano" "$out" "cc-logs.json: kept=0 dropped=1 total=1"

# --- 5. real run: old dropped, recent kept; stop+restart fired; sentinel gone ---
S="$(new_store real)"
rm -f "$TMP/stopped.marker" "$TMP/restarted.marker"
{
  log_line "$RECENT" "$RECENT"
  log_line "$OLD" "$OLD"
} >"$S/cc-logs.json"
{
  metric_line "$RECENT" "$RECENT"
  metric_line "$OLD" "$OLD"
} >"$S/cc-metrics.json"
out="$(run_prune "$S")"
rc=$?
assert_eq "real run exits 0" "0" "$rc"
assert_contains "real run action=pruned" "$out" "action=pruned"
assert_eq "cc-logs trimmed to 1 kept line" "1" "$(wc -l <"$S/cc-logs.json" | tr -d ' \r')"
assert_eq "cc-metrics trimmed to 1 kept line" "1" "$(wc -l <"$S/cc-metrics.json" | tr -d ' \r')"
assert_contains "kept line is the recent one (logs)" "$(cat "$S/cc-logs.json")" "$RECENT"
assert_not_contains "old line removed (logs)" "$(cat "$S/cc-logs.json")" "$OLD"
if [[ -f "$TMP/stopped.marker" ]]; then pass "real run stopped the Collector"; else fail "real run stopped the Collector" "stopped.marker" "absent"; fi
if [[ -f "$TMP/restarted.marker" ]]; then pass "real run restarted the Collector"; else fail "real run restarted the Collector" "restarted.marker" "absent"; fi
if [[ -d "$S/.prune-in-progress" ]]; then fail "sentinel removed after run" "absent" "present"; else pass "sentinel removed after run"; fi

# --- 5b. all-stale: every record older than cutoff -> file emptied (kept==0 path) ---
S="$(new_store allstale)"
rm -f "$TMP/stopped.marker"
{
  log_line "$OLD" "$OLD"
  log_line "$OLD" "$OLD"
} >"$S/cc-logs.json"
out="$(run_prune "$S")"
rc=$?
assert_eq "all-stale real run exits 0" "0" "$rc"
assert_contains "all-stale => action=pruned" "$out" "action=pruned"
assert_eq "all-stale file emptied to 0 lines" "0" "$(wc -l <"$S/cc-logs.json" | tr -d ' \r')"
if [[ -f "$S/cc-logs.json.prune.tmp" ]]; then fail "all-stale cleaned up temp" "absent" "temp left behind"; else pass "all-stale cleaned up temp"; fi
if [[ -d "$S/.prune-in-progress" ]]; then fail "all-stale sentinel removed" "absent" "present"; else pass "all-stale sentinel removed"; fi

# --- 6. all-recent: dry-check short-circuits (no stop, no mutation, no cold/) ---
S="$(new_store allrecent)"
rm -f "$TMP/stopped.marker"
{
  log_line "$RECENT" "$RECENT"
  log_line "$RECENT" "$RECENT"
} >"$S/cc-logs.json"
out="$(run_prune "$S")"
assert_contains "all-recent => nothing-to-prune" "$out" "action=noop-nothing-to-prune"
assert_eq "all-recent leaves file unchanged" "2" "$(wc -l <"$S/cc-logs.json" | tr -d ' \r')"
assert_not_contains "all-recent never stops Collector" "$(ls "$TMP")" "stopped.marker"
if [[ -d "$S/cold" ]]; then
  fail "all-recent noop creates no cold dir" "absent" "present"
else
  pass "all-recent noop creates no cold dir"
fi

# --- 7. partial trailing line (no timeUnixNano) is dropped ---
S="$(new_store partial)"
log_line "$RECENT" "$RECENT" >"$S/cc-logs.json"
printf '{"truncatedBatchNoTimestamp' >>"$S/cc-logs.json" # truncated, no newline, no timeUnixNano
out="$(run_prune "$S")"
assert_contains "partial line dropped" "$out" "action=pruned"
assert_eq "only the complete recent line survives" "1" "$(wc -l <"$S/cc-logs.json" | tr -d ' \r')"
assert_not_contains "partial fragment removed" "$(cat "$S/cc-logs.json")" "truncatedBatchNoTimestamp"

# --- 8. lock: pre-existing sentinel => noop-locked, no stop, no mutation ---
S="$(new_store locked)"
mkdir -p "$S/.prune-in-progress"
rm -f "$TMP/stopped.marker"
{
  log_line "$RECENT" "$RECENT"
  log_line "$OLD" "$OLD"
} >"$S/cc-logs.json"
out="$(run_prune "$S")"
assert_contains "lock held => noop-locked" "$out" "action=noop-locked"
assert_eq "locked run leaves file unchanged" "2" "$(wc -l <"$S/cc-logs.json" | tr -d ' \r')"
assert_not_contains "locked run never stops Collector" "$(ls "$TMP")" "stopped.marker"
rmdir "$S/.prune-in-progress"

# --- 9. verify-before-mv: failed verify aborts, original untouched, exit 1 ---
S="$(new_store verifyfail)"
{
  log_line "$RECENT" "$RECENT"
  log_line "$OLD" "$OLD"
} >"$S/cc-logs.json"
out="$(CC_OTEL_STORE="$S" CC_OTEL_STOP_CMD="$STOP_STUB" CC_OTEL_RUNNING_CMD=false \
  CC_OTEL_VERIFY_CMD=false CC_OTEL_COMPACT_CMD="$COMPACT_STUB" \
  CC_OTEL_START_SCRIPT="$START_STUB" bash "$SCRIPT" 2>&1)"
rc=$?
assert_eq "verify-fail exits 1" "1" "$rc"
assert_contains "verify-fail action" "$out" "action=error-verify-failed"
assert_eq "verify-fail leaves original untouched" "2" "$(wc -l <"$S/cc-logs.json" | tr -d ' \r')"
if [[ -f "$S/cc-logs.json.prune.tmp" ]]; then fail "verify-fail cleaned up temp" "absent" "temp left behind"; else pass "verify-fail cleaned up temp"; fi
if [[ -d "$S/.prune-in-progress" ]]; then fail "verify-fail removed sentinel (trap)" "absent" "present"; else pass "verify-fail removed sentinel (trap)"; fi

# --- 10. metrics footgun: RECENT timeUnixNano + OLD startTimeUnixNano -> kept ---
S="$(new_store footgun-metric)"
metric_line "$RECENT" "$OLD" >"$S/cc-metrics.json"
out="$(run_prune "$S" --dry-run)"
assert_contains "metrics regex keys on timeUnixNano not startTimeUnixNano" "$out" "cc-metrics.json: kept=1 dropped=0 total=1"

# --- 11. knob validation: CC_OTEL_* windows + RETENTION_DAYS guard (all exit 2 pre-store) ---
out="$(CC_OTEL_RETENTION_DAYS=abc bash "$SCRIPT" --dry-run 2>&1)"
rc=$?
assert_eq "non-integer CC_OTEL_RETENTION_DAYS exits 2" "2" "$rc"
assert_contains "CC_OTEL_RETENTION_DAYS validation message" "$out" "CC_OTEL_RETENTION_DAYS must be"
out="$(CC_OTEL_BODY_RETENTION_DAYS=2.5 bash "$SCRIPT" --dry-run 2>&1)"
rc=$?
assert_eq "non-integer CC_OTEL_BODY_RETENTION_DAYS exits 2" "2" "$rc"
assert_contains "CC_OTEL_BODY_RETENTION_DAYS validation message" "$out" "CC_OTEL_BODY_RETENTION_DAYS must be"
out="$(RETENTION_DAYS=5 bash "$SCRIPT" --dry-run 2>&1)"
rc=$?
assert_eq "RETENTION_DAYS alone exits 2" "2" "$rc"
assert_contains "RETENTION_DAYS guard names CC_OTEL_RETENTION_DAYS" "$out" "CC_OTEL_RETENTION_DAYS"
out="$(CC_OTEL_RETENTION_DAYS=3 CC_OTEL_BODY_RETENTION_DAYS=5 bash "$SCRIPT" --dry-run 2>&1)"
rc=$?
assert_eq "body window exceeding structure window exits 2" "2" "$rc"
assert_contains "body>structure rejection message" "$out" "must not exceed"
# RETENTION_DAYS set alongside CC_OTEL_RETENTION_DAYS: CC_OTEL wins; equal windows are allowed.
S="$(new_store knobboth)"
log_line "$RECENT" "$RECENT" >"$S/cc-logs.json"
out="$(RETENTION_DAYS=99 CC_OTEL_RETENTION_DAYS=0 CC_OTEL_BODY_RETENTION_DAYS=0 \
  CC_OTEL_STORE="$S" bash "$SCRIPT" --dry-run 2>&1)"
rc=$?
assert_eq "RETENTION_DAYS ignored when CC_OTEL_RETENTION_DAYS set" "0" "$rc"
assert_contains "new knob wins (1h-old line below 0d cutoff)" "$out" "cc-logs.json: kept=0 dropped=1 total=1"

# --- 12. compact failure (seam): abort BEFORE the hot trim — exit 1, hot byte-unchanged ---
S="$(new_store compactfail)"
rm -f "$TMP/stopped.marker" "$TMP/restarted.marker"
{
  log_line "$RECENT" "$RECENT"
  log_line "$OLD" "$OLD"
} >"$S/cc-logs.json"
{
  metric_line "$RECENT" "$RECENT"
  metric_line "$OLD" "$OLD"
} >"$S/cc-metrics.json"
cp "$S/cc-logs.json" "$TMP/compactfail-logs.bak"
cp "$S/cc-metrics.json" "$TMP/compactfail-metrics.bak"
out="$(CC_OTEL_STORE="$S" CC_OTEL_STOP_CMD="$STOP_STUB" CC_OTEL_RUNNING_CMD=false \
  CC_OTEL_VERIFY_CMD=true CC_OTEL_COMPACT_CMD=false \
  CC_OTEL_START_SCRIPT="$START_STUB" bash "$SCRIPT" 2>&1)"
rc=$?
assert_eq "compact-fail exits 1" "1" "$rc"
assert_contains "compact-fail action" "$out" "action=error-compact-failed"
if cmp -s "$S/cc-logs.json" "$TMP/compactfail-logs.bak"; then pass "compact-fail leaves cc-logs byte-unchanged"; else fail "compact-fail leaves cc-logs byte-unchanged" "byte-identical" "differs"; fi
if cmp -s "$S/cc-metrics.json" "$TMP/compactfail-metrics.bak"; then pass "compact-fail leaves cc-metrics byte-unchanged"; else fail "compact-fail leaves cc-metrics byte-unchanged" "byte-identical" "differs"; fi
if compgen -G "$S/cold/*.parquet" >/dev/null 2>&1; then fail "compact-fail writes no cold parquet" "none" "$(find "$S/cold" -mindepth 1 -maxdepth 1 2>/dev/null | tr '\n' ' ')"; else pass "compact-fail writes no cold parquet"; fi
leaked="$(find "$S" -name '*.tmp' 2>/dev/null)"
assert_eq "compact-fail leaks no temps" "" "$leaked"
if [[ -d "$S/.prune-in-progress" ]]; then fail "compact-fail removed sentinel (trap)" "absent" "present"; else pass "compact-fail removed sentinel (trap)"; fi
if [[ -f "$TMP/restarted.marker" ]]; then pass "compact-fail restarted the Collector (trap)"; else fail "compact-fail restarted the Collector (trap)" "restarted.marker" "absent"; fi

# --- 13. real compaction (duckdb): aged records land in cold Parquet, B1 boundary holds ---
if [[ "$HAS_DUCKDB" == true ]]; then
  S="$(new_store coldreal)"
  {
    real_log_line "$OLD" tool_decision claude_code.tool_decision "$TOOL_EXTRA"
    real_log_line "$OLD" api_request_body claude_code.api_request_body "$API_EXTRA"
    real_log_line "$OLD" user_prompt claude_code.user_prompt "$PROMPT_EXTRA"
    real_log_line "$RECENT" tool_decision claude_code.tool_decision "$TOOL_EXTRA"
  } >"$S/cc-logs.json"
  out="$(run_prune_real "$S")"
  rc=$?
  glob="$(sql_path "$S")/cold/cc-logs-*.parquet"
  assert_eq "real compaction exits 0" "0" "$rc"
  assert_contains "real compaction action=pruned" "$out" "action=pruned"
  assert_eq "one cold logs parquet written" "1" "$(find "$S/cold" -name 'cc-logs-*.parquet' 2>/dev/null | wc -l | tr -d ' ')"
  assert_eq "cold excludes api_*_body rows" "0" "$(dq "SELECT count(*) FROM read_parquet('$glob') WHERE event_name IN ('api_request_body','api_response_body');")"
  assert_eq "cold rows = structure + user_prompt" "2" "$(dq "SELECT count(*) FROM read_parquet('$glob');")"
  assert_eq "user_prompt kept with body NULL + join keys" "1" "$(dq "SELECT count(*) FROM read_parquet('$glob') WHERE event_name='user_prompt' AND body IS NULL AND session_id IS NOT NULL AND prompt_id IS NOT NULL;")"
  assert_eq "prompt text scrubbed from cold" "0" "$(dq "SELECT count(*) FROM read_parquet('$glob') WHERE CAST(log_attributes_raw AS VARCHAR) LIKE '%SECRET_PROMPT_SENTINEL%';")"
  assert_eq "api body content absent from cold" "0" "$(dq "SELECT count(*) FROM read_parquet('$glob') WHERE CAST(log_attributes_raw AS VARCHAR) LIKE '%API_BODY_SENTINEL%';")"
  assert_eq "join keys populated on structure row" "1" "$(dq "SELECT count(*) FROM read_parquet('$glob') WHERE event_name='tool_decision' AND session_id IS NOT NULL AND prompt_id IS NOT NULL AND tool_use_id IS NOT NULL AND trace_id IS NOT NULL AND span_id IS NOT NULL;")"
  assert_eq "hot trimmed to the recent line" "1" "$(wc -l <"$S/cc-logs.json" | tr -d ' \r')"
  assert_contains "hot kept the RECENT line" "$(cat "$S/cc-logs.json")" "$RECENT"
  leaked="$(find "$S" -name '*.tmp' 2>/dev/null)"
  assert_eq "real compaction leaks no temps" "" "$leaked"
else
  skip_case "duckdb not found — skipping real cold-compaction case"
fi

# --- 14. prompt-keep toggle: CC_OTEL_COLD_KEEP_USER_PROMPTS=1 keeps prompt + body in cold ---
if [[ "$HAS_DUCKDB" == true ]]; then
  S="$(new_store coldtoggle)"
  {
    real_log_line "$OLD" user_prompt claude_code.user_prompt "$PROMPT_EXTRA"
    real_log_line "$RECENT" tool_decision claude_code.tool_decision "$TOOL_EXTRA"
  } >"$S/cc-logs.json"
  out="$(CC_OTEL_STORE="$S" CC_OTEL_STOP_CMD="$STOP_STUB" CC_OTEL_RUNNING_CMD=false \
    CC_OTEL_START_SCRIPT="$START_STUB" CC_OTEL_COLD_KEEP_USER_PROMPTS=1 bash "$SCRIPT" 2>&1)"
  rc=$?
  glob="$(sql_path "$S")/cold/cc-logs-*.parquet"
  assert_eq "toggle run exits 0" "0" "$rc"
  assert_eq "toggle keeps prompt attribute + body in cold" "1" "$(dq "SELECT count(*) FROM read_parquet('$glob') WHERE event_name='user_prompt' AND body IS NOT NULL AND CAST(log_attributes_raw AS VARCHAR) LIKE '%SECRET_PROMPT_SENTINEL%';")"
else
  skip_case "duckdb not found — skipping prompt-keep toggle case"
fi

# --- 15. metrics compaction (duckdb): aged metric lines land in cold, no exclusions ---
if [[ "$HAS_DUCKDB" == true ]]; then
  S="$(new_store coldmetrics)"
  {
    real_metric_line "$OLD" claude_code.token.usage '"asInt":"123"'
    real_metric_line "$OLD" claude_code.cost.usage '"asDouble":0.5'
    real_metric_line "$RECENT" claude_code.token.usage '"asInt":"9"'
  } >"$S/cc-metrics.json"
  out="$(run_prune_real "$S")"
  rc=$?
  mglob="$(sql_path "$S")/cold/cc-metrics-*.parquet"
  assert_eq "metrics compaction exits 0" "0" "$rc"
  assert_eq "one cold metrics parquet written" "1" "$(find "$S/cold" -name 'cc-metrics-*.parquet' 2>/dev/null | wc -l | tr -d ' ')"
  assert_eq "cold metrics rows = all aged points" "2" "$(dq "SELECT count(*) FROM read_parquet('$mglob');")"
  assert_eq "cold metrics values + session ids intact" "2" "$(dq "SELECT count(*) FROM read_parquet('$mglob') WHERE value IS NOT NULL AND session_id IS NOT NULL;")"
  assert_eq "metrics hot trimmed to the recent line" "1" "$(wc -l <"$S/cc-metrics.json" | tr -d ' \r')"
else
  skip_case "duckdb not found — skipping metrics cold-compaction case"
fi

# --- 15b. schema-thin metrics slice (duckdb): asDouble-only dropped lines still compact ---
# Real-data regression: a dropped temp is an arbitrary slice — read_json_auto infers ONLY the
# sub-keys present in it, and a slice whose sums are all asDouble (token/cost usage days) has
# no asInt key for a native dp.asInt reference to bind against. Caught live by the Phase 1
# tail-slice probe; the projection must tolerate either sum kind being wholly absent.
if [[ "$HAS_DUCKDB" == true ]]; then
  S="$(new_store coldmetricsthin)"
  {
    real_metric_line "$OLD" claude_code.cost.usage '"asDouble":0.25'
    real_metric_line "$OLD" claude_code.cost.usage '"asDouble":1.5'
    real_metric_line "$RECENT" claude_code.cost.usage '"asDouble":0.1'
  } >"$S/cc-metrics.json"
  out="$(run_prune_real "$S")"
  rc=$?
  mglob="$(sql_path "$S")/cold/cc-metrics-*.parquet"
  assert_eq "asDouble-only metrics compaction exits 0" "0" "$rc"
  assert_eq "asDouble-only cold rows complete with values" "2" "$(dq "SELECT count(*) FROM read_parquet('$mglob') WHERE value IS NOT NULL;")"
  S="$(new_store coldmetricsthinint)"
  {
    real_metric_line "$OLD" claude_code.session.count '"asInt":"3"'
    real_metric_line "$RECENT" claude_code.session.count '"asInt":"1"'
  } >"$S/cc-metrics.json"
  out="$(run_prune_real "$S")"
  rc=$?
  mglob="$(sql_path "$S")/cold/cc-metrics-*.parquet"
  assert_eq "asInt-only metrics compaction exits 0" "0" "$rc"
  assert_eq "asInt-only cold row value cast intact" "3.0" "$(dq "SELECT value FROM read_parquet('$mglob');")"
else
  skip_case "duckdb not found — skipping schema-thin metrics case"
fi

# --- 16. window knobs honored at runtime (structure + body) ---
S="$(new_store knobstructure)"
real_log_line "$MID" tool_decision claude_code.tool_decision "$TOOL_EXTRA" >"$S/cc-logs.json"
out="$(CC_OTEL_STORE="$S" bash "$SCRIPT" --dry-run 2>&1)"
assert_contains "4d-old structure line kept by default 7d window" "$out" "cc-logs.json: kept=1 dropped=0 total=1"
out="$(CC_OTEL_RETENTION_DAYS=3 CC_OTEL_BODY_RETENTION_DAYS=2 CC_OTEL_STORE="$S" bash "$SCRIPT" --dry-run 2>&1)"
assert_contains "4d-old structure line dropped by 3d window" "$out" "cc-logs.json: kept=0 dropped=1 total=1"
S="$(new_store knobbody)"
real_log_line "$RECENT" api_request_body claude_code.api_request_body "$API_EXTRA" >"$S/cc-logs.json"
out="$(CC_OTEL_STORE="$S" bash "$SCRIPT" --dry-run 2>&1)"
assert_contains "1h-old body line untouched by default 2d body window" "$out" "cc-logs.json: kept=1 dropped=0 total=1"
out="$(CC_OTEL_BODY_RETENTION_DAYS=0 CC_OTEL_STORE="$S" bash "$SCRIPT" --dry-run 2>&1)"
assert_contains "1h-old body line routed to surgery by 0d body window" "$out" "cc-logs.json: kept=0 dropped=0 total=1 surgery=1"

# --- 17. record surgery: mixed line past the body window keeps structure records in hot ---
S="$(new_store surgery)"
{
  real_log_batch "$(log_record_json "$MID" tool_decision claude_code.tool_decision "$TOOL_EXTRA"),$(log_record_json "$MID" api_request_body claude_code.api_request_body "$API_EXTRA")"
  real_log_line "$RECENT" tool_decision claude_code.tool_decision "$TOOL_EXTRA"
} >"$S/cc-logs.json"
out="$(run_prune "$S")"
rc=$?
assert_eq "surgery run exits 0" "0" "$rc"
assert_contains "surgery run action=pruned" "$out" "action=pruned"
assert_eq "hot keeps 2 lines (kept verbatim + surgered)" "2" "$(wc -l <"$S/cc-logs.json" | tr -d ' \r')"
assert_contains "surgered structure record survives in hot" "$(cat "$S/cc-logs.json")" '"stringValue":"tool_decision"'
assert_not_contains "api body content stripped from hot" "$(cat "$S/cc-logs.json")" "API_BODY_SENTINEL"
assert_not_contains "api_request_body record gone from hot" "$(cat "$S/cc-logs.json")" '"stringValue":"api_request_body"'
assert_contains "per-file surgery counts reported" "$out" "surgery_kept=1 surgery_dropped=0"
if compgen -G "$S/cold/*.parquet" >/dev/null 2>&1; then
  fail "surgery alone writes no cold parquet" "none" "$(find "$S/cold" -mindepth 1 -maxdepth 1 2>/dev/null | tr '\n' ' ')"
else
  pass "surgery alone writes no cold parquet"
fi
leaked="$(find "$S" -name '*.tmp' 2>/dev/null)"
assert_eq "surgery leaks no temps" "" "$leaked"
if [[ "$HAS_DUCKDB" == true ]]; then
  hot="$(sql_path "$S/cc-logs.json")"
  assert_eq "duckdb: hot tool_decision records = 2" "2" "$(dq_macro "SELECT count(*) FROM cc_logs_from('$hot') WHERE event_name='tool_decision';")"
  assert_eq "duckdb: hot api body records = 0" "0" "$(dq_macro "SELECT count(*) FROM cc_logs_from('$hot') WHERE event_name IN ('api_request_body','api_response_body');")"
else
  skip_case "duckdb not found — skipping surgery event_name counts"
fi

# --- 18. pure-body line past the body window is removed entirely (zero-record batch) ---
S="$(new_store purebody)"
{
  real_log_line "$MID" api_request_body claude_code.api_request_body "$API_EXTRA"
  real_log_line "$RECENT" tool_decision claude_code.tool_decision "$TOOL_EXTRA"
} >"$S/cc-logs.json"
out="$(run_prune "$S")"
rc=$?
assert_eq "pure-body run exits 0" "0" "$rc"
assert_eq "pure-body line removed entirely from hot" "1" "$(wc -l <"$S/cc-logs.json" | tr -d ' \r')"
assert_not_contains "no body content left in hot" "$(cat "$S/cc-logs.json")" "API_BODY_SENTINEL"
assert_contains "pure-body drop reported" "$out" "surgery_kept=0 surgery_dropped=1"
if compgen -G "$S/cold/*.parquet" >/dev/null 2>&1; then
  fail "surgered body records do not reach cold" "none" "$(find "$S/cold" -mindepth 1 -maxdepth 1 2>/dev/null | tr '\n' ' ')"
else
  pass "surgered body records do not reach cold"
fi

# --- 19. body-bearing line NEWER than the body window stays byte-identical through a prune ---
S="$(new_store bodyrecent)"
real_log_batch "$(log_record_json "$RECENT" tool_decision claude_code.tool_decision "$TOOL_EXTRA"),$(log_record_json "$RECENT" api_request_body claude_code.api_request_body "$API_EXTRA")" >"$TMP/bodyrecent-expected.line"
cat "$TMP/bodyrecent-expected.line" >"$S/cc-logs.json"
real_log_line "$OLD" tool_decision claude_code.tool_decision "$TOOL_EXTRA" >>"$S/cc-logs.json"
out="$(run_prune "$S")"
rc=$?
assert_eq "recent-body run exits 0" "0" "$rc"
if cmp -s "$S/cc-logs.json" "$TMP/bodyrecent-expected.line"; then
  pass "recent body line byte-identical after prune"
else
  fail "recent body line byte-identical after prune" "byte-identical" "differs"
fi

# --- 20. footgun: literal escaped marker text inside a string value is NOT a body line ---
S="$(new_store footgun-content)"
real_log_line "$MID" tool_decision claude_code.tool_decision "$FOOTGUN_EXTRA" >"$S/cc-logs.json"
out="$(CC_OTEL_STORE="$S" bash "$SCRIPT" --dry-run 2>&1)"
assert_contains "escaped marker content stays a kept structure line" "$out" "cc-logs.json: kept=1 dropped=0 total=1 surgery=0"

# --- 21. dry-run per-class counts: structure kept/dropped, body surgery/dropped, would-compact ---
S="$(new_store dryclass)"
{
  real_log_line "$OLD" tool_decision claude_code.tool_decision "$TOOL_EXTRA"      # whole-line drop -> cold
  real_log_line "$OLD" api_request_body claude_code.api_request_body "$API_EXTRA" # body line past structure window -> whole-line drop
  real_log_batch "$(log_record_json "$MID" tool_decision claude_code.tool_decision "$TOOL_EXTRA"),$(log_record_json "$MID" api_request_body claude_code.api_request_body "$API_EXTRA")"
  real_log_line "$RECENT" tool_decision claude_code.tool_decision "$TOOL_EXTRA" # kept verbatim
} >"$S/cc-logs.json"
before="$(cat "$S/cc-logs.json")"
out="$(run_prune "$S" --dry-run)"
rc=$?
assert_eq "per-class dry-run exits 0" "0" "$rc"
assert_contains "per-class dry-run counts" "$out" "cc-logs.json: kept=1 dropped=2 total=4 surgery=1 body_dropped=1 would_compact=2"
assert_contains "dry-run totals include surgery" "$out" "action=dry-run total_dropped=2 total_surgery=1"
assert_eq "per-class dry-run mutates nothing" "$before" "$(cat "$S/cc-logs.json")"
if [[ -d "$S/cold" ]]; then
  fail "per-class dry-run creates no cold dir" "absent" "present"
else
  pass "per-class dry-run creates no cold dir"
fi
leaked="$(find "$S" -name '*.tmp' 2>/dev/null)"
assert_eq "per-class dry-run writes no temps" "" "$leaked"

# --- 22. jq round-trip: surgered line re-parses via duckdb; double literal preserved exactly ---
S="$(new_store roundtrip)"
real_log_batch "$(log_record_json "$MID" tool_decision claude_code.tool_decision "$DOUBLE_EXTRA"),$(log_record_json "$MID" api_request_body claude_code.api_request_body "$API_EXTRA")" >"$S/cc-logs.json"
out="$(run_prune "$S")"
rc=$?
assert_eq "round-trip run exits 0" "0" "$rc"
assert_contains "doubleValue literal preserved through surgery" "$(cat "$S/cc-logs.json")" '"doubleValue":123.456'
if [[ "$HAS_DUCKDB" == true ]]; then
  assert_eq "surgered hot file re-parses via duckdb" "1" "$(dq "SELECT count(*) FROM read_json_auto('$(sql_path "$S/cc-logs.json")', format='newline_delimited', maximum_object_size=33554432, sample_size=-1);")"
else
  skip_case "duckdb not found — skipping surgered round-trip parse"
fi

# --- 23. Traces: age routing keys on startTimeUnixNano (not timeUnixNano) ---
S="$(new_store traces-age)"
trace_line "$OLD" >"$S/cc-traces.json"
out="$(run_prune "$S")"
rc=$?
assert_eq "traces-age run exits 0" "0" "$rc"
assert_contains "traces route by startTimeUnixNano" "$out" "cc-traces.json: kept=0 dropped=1 total=1"
assert_eq "stale trace line removed" "0" "$(wc -l <"$S/cc-traces.json" | tr -d ' \r')"

# --- 24. Traces cold compaction: user_prompt scrubbed (real duckdb path) ---
if [[ "$HAS_DUCKDB" == true ]]; then
  S="$(new_store traces-cold)"
  real_trace_line "$OLD" claude_code.interaction "$SPAN_PROMPT_EXTRA" >"$S/cc-traces.json"
  out="$(run_prune_real "$S")"
  rc=$?
  assert_eq "traces cold run exits 0" "0" "$rc"
  tglob="$(sql_path "$S")/cold/cc-traces-*.parquet"
  assert_eq "one cold traces parquet written" "1" "$(find "$S/cold" -name 'cc-traces-*.parquet' 2>/dev/null | wc -l | tr -d ' ')"
  assert_eq "cold span row count" "1" "$(dq "SELECT count(*) FROM read_parquet('$tglob');")"
  assert_eq "cold user_prompt column NULLed" "1" "$(dq_macro "SELECT count(*) FROM cc_spans_cold('$(sql_path "$S")/cold/cc-traces-*.parquet') WHERE user_prompt IS NULL;")"
  assert_eq "cold prompt attribute scrubbed from raw" "0" "$(dq_macro "SELECT count(*) FROM cc_spans_cold('$(sql_path "$S")/cold/cc-traces-*.parquet') WHERE span_attributes_raw LIKE '%SECRET_PROMPT_SENTINEL%';")"
else
  skip_case "duckdb not found — skipping traces cold compaction"
fi

printf '\n%d passed, %d failed\n' "$((CASE_NUM - FAILED))" "$FAILED"
[[ "$FAILED" -eq 0 ]]
