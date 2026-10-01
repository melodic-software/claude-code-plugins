#!/usr/bin/env bash
# Black-box contract tests for prune-otel-store.sh.
# Drives the script as a subprocess against a FIXTURE store with the Collector service
# stop/running/start and verify/compact hooks stubbed (CC_OTEL_*_CMD seams) — it never
# touches the real machine Collector or the real store.
#
# Two fixture grades:
#   - log_line/metric_line: minimal lines for trim-mechanics cases (lock, verify, dry-run, …).
#     These run with the compact seam stubbed (COMPACT_STUB) so they stay hermetic — no duckdb.
#   - real_log_line/real_metric_line: realistic OTLP/JSON shapes (resource+scope envelope,
#     typed attributes, traceId/spanId) for the cold-compaction cases, which run the REAL
#     duckdb COPY path and assert on cold Parquet CONTENT (state-based). Those cases gate on
#     `command -v duckdb` -> skip_case (CI installs duckdb in ci.yml test-linux).

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR
readonly SCRIPT="$SCRIPT_DIR/prune-otel-store.sh"
readonly LIFECYCLE="$SCRIPT_DIR/prune-collector-lifecycle.sh"

# Inline test helpers — self-contained, no external test lib (ships with the plugin).
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
assert_contains() { if [[ "$2" == *"$3"* ]]; then pass "$1"; else fail "$1" "contains: $3" "$2"; fi; }
assert_not_contains() { if [[ "$2" != *"$3"* ]]; then pass "$1"; else fail "$1" "absent: $3" "$2"; fi; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# Hermeticity: the developer's environment must not leak retention knobs into the cases
# (RETENTION_DAYS guard would trip every run if RETENTION_DAYS were exported machine-wide).
unset RETENTION_DAYS CC_OTEL_RETENTION_DAYS CC_OTEL_BODY_RETENTION_DAYS CC_OTEL_COLD_KEEP_USER_PROMPTS

# Stubs: stop hook + restart script touch markers so invocation is assertable; the compact
# stub mimics a successful duckdb COPY by creating the cold temp it is handed ($2).
STOP_STUB="$TMP/stop-stub.sh"
START_STUB="$TMP/start-stub.sh"
QUERY_ERROR_STUB="$TMP/query-error-stub.sh"
COMPACT_STUB="$TMP/compact-stub.sh"
printf '#!/usr/bin/env bash\ntouch "%s/stopped.marker"\n' "$TMP" >"$STOP_STUB"
# The restart seam also launches a child lock contender. It must lose while the first prune's
# sentinel remains held; this proves restart-before-release ordering with a separate process.
# shellcheck disable=SC2016  # literal CC_OTEL_STORE expansion must reach the stub script
printf '#!/usr/bin/env bash\n( if mkdir "${CC_OTEL_STORE:?}/.prune-in-progress" 2>/dev/null; then exit 1; else touch "%s/concurrent-blocked.marker"; fi )\nwait\ntouch "%s/restarted.marker"\n' \
  "$TMP" "$TMP" >"$START_STUB"
printf '#!/usr/bin/env bash\nexit 2\n' >"$QUERY_ERROR_STUB"
# shellcheck disable=SC2016  # literal $2 must reach the stub script unexpanded
printf '#!/usr/bin/env bash\n: >"$2"\n' >"$COMPACT_STUB"
chmod +x "$STOP_STUB" "$START_STUB" "$QUERY_ERROR_STUB" "$COMPACT_STUB"

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
readonly TOOL_DECISION_SOURCE_EXTRA=',{"key":"tool_name","value":{"stringValue":"Bash"}},{"key":"tool_use_id","value":{"stringValue":"toolu-1"}},{"key":"decision","value":{"stringValue":"reject"}},{"key":"source","value":{"stringValue":"config"}}'
readonly PROMPT_EXTRA=',{"key":"prompt","value":{"stringValue":"SECRET_PROMPT_SENTINEL"}},{"key":"prompt_text","value":{"stringValue":"SECRET_PROMPT_TEXT_SENTINEL"}},{"key":"prompt_length","value":{"stringValue":"22"}}'
readonly SPAN_PROMPT_EXTRA=',{"key":"user_prompt","value":{"stringValue":"SECRET_PROMPT_SENTINEL"}},{"key":"prompt_text","value":{"stringValue":"SECRET_PROMPT_TEXT_SENTINEL"}}'
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
    CC_OTEL_START_CMD="$START_STUB" \
    bash "$SCRIPT" "${@:2}" 2>&1
}
run_prune_real() { # <store_dir> <args...>; machine-protection stubs only — REAL duckdb verify + compaction
  CC_OTEL_STORE="$1" \
    CC_OTEL_STOP_CMD="$STOP_STUB" \
    CC_OTEL_RUNNING_CMD=false \
    CC_OTEL_START_CMD="$START_STUB" \
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

# --- lifecycle contract: fixed Windows service verbs, never process-name killing ---
lifecycle_source="$(cat "$LIFECYCLE")"
assert_contains "lifecycle targets the fixed collector service" "$lifecycle_source" \
  "COLLECTOR_SERVICE_NAME='otelcol-contrib'"
assert_contains "lifecycle stops through the service controller" "$lifecycle_source" "Stop-Service -Name"
assert_contains "lifecycle starts through the service controller" "$lifecycle_source" "Start-Service -Name"
assert_contains "lifecycle polls service status" "$lifecycle_source" "Get-Service -Name"
assert_not_contains "lifecycle no longer kills processes" "$lifecycle_source" "Stop-Process"
assert_not_contains "lifecycle no longer matches process command lines" "$lifecycle_source" "Win32_Process"

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
if [[ -e "$S/.last-prune" ]]; then fail "--dry-run writes no last-prune stamp" "absent" "present"; else pass "--dry-run writes no last-prune stamp"; fi

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
if [[ -f "$TMP/concurrent-blocked.marker" ]]; then pass "restart runs while sentinel still blocks a concurrent prune"; else fail "restart runs while sentinel still blocks a concurrent prune" "concurrent-blocked.marker" "absent"; fi
if [[ -d "$S/.prune-in-progress" ]]; then fail "sentinel removed after run" "absent" "present"; else pass "sentinel removed after run"; fi
stamp="$(cat "$S/.last-prune" 2>/dev/null)"
if [[ "$stamp" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$ ]]; then pass "real run writes an ISO-8601 UTC last-prune stamp"; else fail "real run writes an ISO-8601 UTC last-prune stamp" "ISO-8601 Z" "$stamp"; fi

# --- 5a. stop denial/failure: abort before mutation and do not attempt a start ---
S="$(new_store stopfail)"
rm -f "$TMP/restarted.marker"
{
  log_line "$RECENT" "$RECENT"
  log_line "$OLD" "$OLD"
} >"$S/cc-logs.json"
before="$(cat "$S/cc-logs.json")"
out="$(CC_OTEL_STORE="$S" CC_OTEL_STOP_CMD=false CC_OTEL_RUNNING_CMD=false \
  CC_OTEL_VERIFY_CMD=true CC_OTEL_COMPACT_CMD="$COMPACT_STUB" \
  CC_OTEL_START_CMD="$START_STUB" bash "$SCRIPT" 2>&1)"
rc=$?
assert_eq "stop failure exits nonzero" "1" "$rc"
assert_eq "stop failure leaves the store byte-identical" "$before" "$(cat "$S/cc-logs.json")"
if [[ -d "$S/.prune-in-progress" ]]; then fail "stop failure removes sentinel" "absent" "present"; else pass "stop failure removes sentinel"; fi
assert_not_contains "stop failure does not start a service it never stopped" "$(ls "$TMP")" "restarted.marker"

# --- 5b. start failure: trim lands, restart is attempted under lock, then failure is visible ---
S="$(new_store startfail)"
{
  log_line "$RECENT" "$RECENT"
  log_line "$OLD" "$OLD"
} >"$S/cc-logs.json"
out="$(CC_OTEL_STORE="$S" CC_OTEL_STOP_CMD="$STOP_STUB" CC_OTEL_RUNNING_CMD=false \
  CC_OTEL_VERIFY_CMD=true CC_OTEL_COMPACT_CMD="$COMPACT_STUB" \
  CC_OTEL_START_CMD=false bash "$SCRIPT" 2>&1)"
rc=$?
assert_eq "start failure exits nonzero" "1" "$rc"
assert_contains "start failure is visible" "$out" "failed to restart Collector service"
assert_eq "start failure occurs after the verified trim" "1" "$(wc -l <"$S/cc-logs.json" | tr -d ' \r')"
if [[ -d "$S/.prune-in-progress" ]]; then fail "start failure removes sentinel" "absent" "present"; else pass "start failure removes sentinel"; fi
assert_eq "start failure writes no last-prune stamp" "absent" "$([[ -e "$S/.last-prune" ]] && echo present || echo absent)"

# --- 5c. service-query error: fail closed before mutation, then recover + release lock ---
S="$(new_store querystatusfail)"
rm -f "$TMP/restarted.marker" "$TMP/concurrent-blocked.marker"
{
  log_line "$RECENT" "$RECENT"
  log_line "$OLD" "$OLD"
} >"$S/cc-logs.json"
before="$(cat "$S/cc-logs.json")"
out="$(CC_OTEL_STORE="$S" CC_OTEL_STOP_CMD="$STOP_STUB" CC_OTEL_RUNNING_CMD="$QUERY_ERROR_STUB" \
  CC_OTEL_VERIFY_CMD=true CC_OTEL_COMPACT_CMD="$COMPACT_STUB" \
  CC_OTEL_START_CMD="$START_STUB" bash "$SCRIPT" 2>&1)"
rc=$?
assert_eq "service-query error exits nonzero" "1" "$rc"
assert_contains "service-query error is distinct from Stopped" "$out" "action=error-collector-status-query"
assert_eq "service-query error leaves the store byte-identical" "$before" "$(cat "$S/cc-logs.json")"
if [[ -f "$TMP/restarted.marker" ]]; then pass "service-query error restarts the stopped Collector"; else fail "service-query error restarts the stopped Collector" "restarted.marker" "absent"; fi
if [[ -f "$TMP/concurrent-blocked.marker" ]]; then pass "service-query recovery restart remains under lock"; else fail "service-query recovery restart remains under lock" "concurrent-blocked.marker" "absent"; fi
if [[ -d "$S/.prune-in-progress" ]]; then fail "service-query error removes sentinel last" "absent" "present"; else pass "service-query error removes sentinel last"; fi

# --- 5d. all-stale: every record older than cutoff -> file emptied (kept==0 path) ---
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

# --- 8a. lock race: sixteen acquirers in a tight loop, never two holders at once ---
# Whole prunes start too far apart to race; uutils mkdir (Ubuntu 25.10+) let two racers both
# win, which only a tight loop like this reproduces.
race_log="$TMP/sentinel-race.log"
: >"$race_log"
for _ in $(seq 16); do
  # shellcheck disable=SC2016  # the inner script expands its own variables
  bash -c 'err() { :; }; source "$1"; SENTINEL="$2"
    for _ in $(seq 200); do
      take_sentinel || continue
      printf "in %s\n" "$$" >>"$3"; sleep 0.01; printf "out %s\n" "$$" >>"$3"
      release_sentinel
    done' _ "$LIFECYCLE" "$TMP/race-sentinel" "$race_log" &
done
wait
assert_eq "racing prunes hold the sentinel one at a time" "ok" \
  "$(awk '$1=="in"{if(h!="")bad=1;h=$2;n++} $1=="out"{if(h!=$2)bad=1;h=""} END{print (bad||!n||h!="")?"overlap":"ok"}' "$race_log")"

# --- 9. verify-before-mv: failed verify aborts, original untouched, exit 1 ---
S="$(new_store verifyfail)"
{
  log_line "$RECENT" "$RECENT"
  log_line "$OLD" "$OLD"
} >"$S/cc-logs.json"
out="$(CC_OTEL_STORE="$S" CC_OTEL_STOP_CMD="$STOP_STUB" CC_OTEL_RUNNING_CMD=false \
  CC_OTEL_VERIFY_CMD=false CC_OTEL_COMPACT_CMD="$COMPACT_STUB" \
  CC_OTEL_START_CMD="$START_STUB" bash "$SCRIPT" 2>&1)"
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
  CC_OTEL_START_CMD="$START_STUB" bash "$SCRIPT" 2>&1)"
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
  assert_eq "prompt_text attribute scrubbed from cold" "0" "$(dq "SELECT count(*) FROM read_parquet('$glob') WHERE CAST(log_attributes_raw AS VARCHAR) LIKE '%SECRET_PROMPT_TEXT_SENTINEL%';")"
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
    CC_OTEL_START_CMD="$START_STUB" CC_OTEL_COLD_KEEP_USER_PROMPTS=1 bash "$SCRIPT" 2>&1)"
  rc=$?
  glob="$(sql_path "$S")/cold/cc-logs-*.parquet"
  assert_eq "toggle run exits 0" "0" "$rc"
  assert_eq "toggle keeps prompt attribute + body in cold" "1" "$(dq "SELECT count(*) FROM read_parquet('$glob') WHERE event_name='user_prompt' AND body IS NOT NULL AND CAST(log_attributes_raw AS VARCHAR) LIKE '%SECRET_PROMPT_SENTINEL%';")"
  assert_eq "toggle keeps prompt_text attribute in cold" "1" "$(dq "SELECT count(*) FROM read_parquet('$glob') WHERE CAST(log_attributes_raw AS VARCHAR) LIKE '%SECRET_PROMPT_TEXT_SENTINEL%';")"
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

# --- 15c. schema-thin logs slice (duckdb): records without traceId/spanId still compact ---
# Real-data regression (#5232): records emitted without tracing carry no traceId/spanId, so a
# dropped temp made only of them has no such key for a native r.traceId reference to bind.
if [[ "$HAS_DUCKDB" == true ]]; then
  S="$(new_store coldlogsthin)"
  {
    real_log_line "$OLD" tool_decision claude_code.tool_decision "$TOOL_EXTRA" | sed 's/,"traceId":"[^"]*","spanId":"[^"]*"//'
    real_log_line "$RECENT" tool_decision claude_code.tool_decision "$TOOL_EXTRA"
  } >"$S/cc-logs.json"
  out="$(run_prune_real "$S")"
  rc=$?
  glob="$(sql_path "$S")/cold/cc-logs-*.parquet"
  assert_eq "traceless logs compaction exits 0" "0" "$rc"
  assert_eq "traceless cold row has NULL trace_id" "1" "$(dq "SELECT count(*) FROM read_parquet('$glob') WHERE trace_id IS NULL AND session_id IS NOT NULL;")"
else
  skip_case "duckdb not found — skipping schema-thin logs case"
fi

# --- 15d. compaction failure surfaces the tool's stderr instead of a bare abort ---
if [[ "$HAS_DUCKDB" == true ]]; then
  S="$(new_store coldbadjson)"
  {
    printf '{"resourceLogs":[{"scopeLogs":[{"logRecords":[{"timeUnixNano":"%s","body":{"stringValue":"x"},"attributes":"not-a-list"}]}]}]}\n' "$OLD"
    real_log_line "$RECENT" tool_decision claude_code.tool_decision "$TOOL_EXTRA"
  } >"$S/cc-logs.json"
  out="$(run_prune_real "$S")"
  assert_contains "compact failure reports duckdb stderr" "$out" "duckdb failed:"
else
  skip_case "duckdb not found — skipping compaction stderr case"
fi

# --- 15e. Windows: a backslash CC_OTEL_STORE (as Machine-scope env delivers it) is usable ---
if [[ "${OSTYPE:-}" == msys* || "${OSTYPE:-}" == cygwin* ]]; then
  S="$(new_store backslash)"
  {
    log_line "$RECENT" "$RECENT"
    log_line "$OLD" "$OLD"
  } >"$S/cc-logs.json"
  out="$(run_prune "$(cygpath -w "$S")")"
  rc=$?
  assert_eq "backslash store path prune exits 0" "0" "$rc"
  assert_contains "backslash store path pruned" "$out" "action=pruned"
  assert_eq "backslash store path trimmed hot file" "1" "$(wc -l <"$S/cc-logs.json" | tr -d ' \r')"
else
  skip_case "not Windows — skipping backslash store path case"
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
  assert_eq "cold prompt_text attribute scrubbed from raw" "0" "$(dq_macro "SELECT count(*) FROM cc_spans_cold('$(sql_path "$S")/cold/cc-traces-*.parquet') WHERE span_attributes_raw LIKE '%SECRET_PROMPT_TEXT_SENTINEL%';")"
else
  skip_case "duckdb not found — skipping traces cold compaction"
fi

# --- 25. cc_logs_from promotes tool_decision `source` (official) and tool_result `decision_source` ---
if [[ "$HAS_DUCKDB" == true ]]; then
  S="$(new_store source-projection)"
  real_log_line "$RECENT" tool_decision tool_decision "$TOOL_DECISION_SOURCE_EXTRA" >"$S/cc-logs.json"
  hot="$(sql_path "$S/cc-logs.json")"
  assert_eq "tool_decision source attr -> source column" "config" \
    "$(dq_macro "SELECT source FROM cc_logs_from('$hot') WHERE event_name='tool_decision' LIMIT 1;")"
  real_log_line "$RECENT" tool_result tool_result \
    ',{"key":"decision_source","value":{"stringValue":"user_temporary"}}' >"$S/cc-logs.json"
  hot="$(sql_path "$S/cc-logs.json")"
  assert_eq "tool_result decision_source attr -> source column" "user_temporary" \
    "$(dq_macro "SELECT source FROM cc_logs_from('$hot') WHERE event_name='tool_result' LIMIT 1;")"
else
  skip_case "duckdb not found — skipping source projection"
fi

# --- 26. size cap: hot file over CC_OTEL_HOT_MAX_MB is pruned though every line is young ---
# 1400 lines of ~1.5KB (~2MB) between 3d and 2.8h ago: inside the 7d window, over a 1 MiB cap.
BIG_SRC="$TMP/big-cc-logs.json"
big_pad="$(printf 'p%.0s' $(seq 1 900))"
: >"$BIG_SRC"
for ((i = 0; i < 1400; i++)); do
  real_log_line "$(mk_nano "$((NOW - 3 * 86400 + i * 10))")" tool_decision "$big_pad" "$TOOL_EXTRA" >>"$BIG_SRC"
done
BIG_NEWEST="$(mk_nano "$((NOW - 3 * 86400 + 1399 * 10))")"
BIG_OLDEST="$(mk_nano "$((NOW - 3 * 86400))")"
readonly CAP_BYTES=1048576

S="$(new_store sizecap)"
cp "$BIG_SRC" "$S/cc-logs.json"
out="$(CC_OTEL_HOT_MAX_MB=1 run_prune "$S" --dry-run)"
rc=$?
assert_eq "size cap dry-run exits 0" "0" "$rc"
assert_contains "dry-run reports the cap" "$out" "hot_max_mb=1"
assert_contains "dry-run names the size-pruned file" "$out" "cc-logs.json: size_prune cutoff_epoch_seconds="
assert_contains "dry-run counts size-pruned files" "$out" "size_pruned_files=1"
assert_eq "dry-run left the over-cap file byte-identical" "$(cksum <"$BIG_SRC")" "$(cksum <"$S/cc-logs.json")"
[[ -e "$TMP/stopped.marker" ]] && rm -f "$TMP/stopped.marker"

out="$(CC_OTEL_HOT_MAX_MB=1 run_prune "$S")"
rc=$?
assert_eq "size cap run exits 0" "0" "$rc"
assert_contains "size cap run prunes (no noop short-circuit)" "$out" "action=pruned"
assert_eq "size cap run stopped the Collector" "yes" "$([[ -e "$TMP/stopped.marker" ]] && echo yes || echo no)"
rm -f "$TMP/stopped.marker"
hot_bytes="$(wc -c <"$S/cc-logs.json" | tr -d ' \r')"
if ((hot_bytes <= CAP_BYTES && hot_bytes > 0)); then pass "hot file fits under the cap and is not emptied"; else fail "hot file fits under the cap and is not emptied" "0 < bytes <= $CAP_BYTES" "$hot_bytes"; fi
assert_contains "newest line survives" "$(cat "$S/cc-logs.json")" "$BIG_NEWEST"
assert_not_contains "oldest line dropped" "$(cat "$S/cc-logs.json")" "\"$BIG_OLDEST\""

# Lines the Collector appends between the preflight and its stop still count toward the cap.
S="$(new_store sizecap-late)"
{
  log_line "$OLD" "$OLD"
  head -n 600 "$BIG_SRC"
} >"$S/cc-logs.json"
tail -n +601 "$BIG_SRC" >"$TMP/late-batches.json"
LATE_STOP="$TMP/late-stop-stub.sh"
printf '#!/usr/bin/env bash\ncat "%s" >>"%s/cc-logs.json"\ntouch "%s/stopped.marker"\n' "$TMP/late-batches.json" "$S" "$TMP" >"$LATE_STOP"
chmod +x "$LATE_STOP"
CC_OTEL_HOT_MAX_MB=1 CC_OTEL_STORE="$S" CC_OTEL_STOP_CMD="$LATE_STOP" CC_OTEL_RUNNING_CMD=false \
  CC_OTEL_VERIFY_CMD=true CC_OTEL_COMPACT_CMD="$COMPACT_STUB" CC_OTEL_START_CMD="$START_STUB" bash "$SCRIPT" >/dev/null 2>&1
hot_bytes="$(wc -c <"$S/cc-logs.json" | tr -d ' \r')"
if ((hot_bytes <= CAP_BYTES && hot_bytes > 0)); then pass "cap holds for lines appended before the Collector stopped"; else fail "cap holds for lines appended before the Collector stopped" "0 < bytes <= $CAP_BYTES" "$hot_bytes"; fi
rm -f "$TMP/stopped.marker"

# Same fixture through the REAL compaction: the size-dropped lines land in cold Parquet.
if [[ "$HAS_DUCKDB" == true ]]; then
  S="$(new_store sizecap-cold)"
  cp "$BIG_SRC" "$S/cc-logs.json"
  out="$(CC_OTEL_HOT_MAX_MB=1 run_prune_real "$S")"
  rc=$?
  assert_eq "size cap real run exits 0" "0" "$rc"
  kept_lines="$(wc -l <"$S/cc-logs.json" | tr -d ' \r')"
  cold_rows="$(dq "SELECT count(*) FROM read_parquet('$(sql_path "$S")/cold/cc-logs-*.parquet');")"
  assert_eq "size-dropped lines all landed in cold" "$((1400 - kept_lines))" "$cold_rows"
  if ((cold_rows > 0)); then pass "size cap dropped rows into cold"; else fail "size cap dropped rows into cold" ">0" "$cold_rows"; fi
else
  skip_case "duckdb not found — skipping size-cap cold compaction"
fi

# Compaction failure on a size drop still aborts before the trim (same posture as age drops).
S="$(new_store sizecap-compactfail)"
cp "$BIG_SRC" "$S/cc-logs.json"
out="$(CC_OTEL_HOT_MAX_MB=1 CC_OTEL_STORE="$S" CC_OTEL_STOP_CMD="$STOP_STUB" CC_OTEL_RUNNING_CMD=false CC_OTEL_VERIFY_CMD=true CC_OTEL_COMPACT_CMD=false CC_OTEL_START_CMD="$START_STUB" bash "$SCRIPT" 2>&1)"
rc=$?
assert_eq "size-drop compaction failure exits 1" "1" "$rc"
assert_eq "size-drop compaction failure leaves hot byte-identical" "$(cksum <"$BIG_SRC")" "$(cksum <"$S/cc-logs.json")"

# --- 27. size cap: under-cap file with young lines is untouched (no-op short-circuit holds) ---
S="$(new_store sizecap-under)"
cp "$BIG_SRC" "$S/cc-logs.json"
rm -f "$TMP/stopped.marker"
out="$(CC_OTEL_HOT_MAX_MB=8 run_prune "$S")"
rc=$?
assert_eq "under-cap run exits 0" "0" "$rc"
assert_contains "under-cap run is a no-op" "$out" "action=noop-nothing-to-prune"
assert_eq "no-op run still writes the last-prune stamp" "yes" "$([[ -s "$S/.last-prune" ]] && echo yes || echo no)"
assert_not_contains "under-cap file not reported as size-pruned" "$out" "size_prune"
assert_eq "under-cap file byte-identical" "$(cksum <"$BIG_SRC")" "$(cksum <"$S/cc-logs.json")"
assert_eq "under-cap run never stopped the Collector" "no" "$([[ -e "$TMP/stopped.marker" ]] && echo yes || echo no)"
out="$(CC_OTEL_HOT_MAX_MB=0 run_prune "$S")"
assert_contains "cap 0 disables the size prune" "$out" "action=noop-nothing-to-prune"

# --- 28. CC_OTEL_HOT_MAX_MB validation: non-integer exits 2 pre-store ---
out="$(CC_OTEL_HOT_MAX_MB=abc bash "$SCRIPT" --dry-run 2>&1)"
rc=$?
assert_eq "non-integer CC_OTEL_HOT_MAX_MB exits 2" "2" "$rc"
assert_contains "CC_OTEL_HOT_MAX_MB validation message" "$out" "CC_OTEL_HOT_MAX_MB must be"

# --- 29. --scrub-cold: dirty cold files rewritten in place, clean ones untouched, notice fires ---
if [[ "$HAS_DUCKDB" == true ]]; then
  S="$(new_store scrubcold)"
  # Dirty cold files: compacted with the keep knob on, so prompt, prompt_text and the
  # user_prompt body/column all reach cold (a superset of a pre-fix pruner's output).
  {
    real_log_line "$OLD" user_prompt claude_code.user_prompt "$PROMPT_EXTRA"
    real_log_line "$OLD" tool_decision claude_code.tool_decision "$TOOL_EXTRA"
    real_log_line "$RECENT" tool_decision claude_code.tool_decision "$TOOL_EXTRA"
  } >"$S/cc-logs.json"
  real_trace_line "$OLD" claude_code.interaction "$SPAN_PROMPT_EXTRA" >"$S/cc-traces.json"
  CC_OTEL_COLD_KEEP_USER_PROMPTS=1 run_prune_real "$S" >/dev/null
  dirty_logs="$(find "$S/cold" -name 'cc-logs-*.parquet')"
  # A clean cold file: a later default-scrub compaction of a structure-only line.
  real_log_line "$OLD" tool_decision claude_code.tool_decision "$TOOL_EXTRA" >>"$S/cc-logs.json"
  out="$(run_prune_real "$S")"
  assert_contains "prune notices cold files holding prompt content" "$out" "notice: 2 cold file(s) still hold prompt content; run prune-otel-store.sh --scrub-cold"
  clean_logs="$(find "$S/cold" -name 'cc-logs-*.parquet' ! -path "$dirty_logs")"
  clean_sum="$(cksum <"$clean_logs")"
  cold_sum() { cat "$S"/cold/*.parquet | cksum; }
  before="$(cold_sum)"

  out="$(run_prune_real "$S" --scrub-cold --dry-run)"
  assert_contains "scrub dry-run lists the dirty logs file" "$out" "cold/${dirty_logs##*/}: would_scrub rows=2 prompt_rows=1"
  assert_contains "scrub dry-run counts affected files" "$out" "action=dry-run-scrub-cold affected_files=2"
  assert_eq "scrub dry-run mutates nothing" "$before" "$(cold_sum)"

  out="$(CC_OTEL_COLD_KEEP_USER_PROMPTS=1 run_prune_real "$S" --scrub-cold)"
  assert_contains "keep knob makes the scrub a no-op" "$out" "action=noop-scrub-cold-keep-user-prompts"
  assert_eq "keep-knob scrub mutates nothing" "$before" "$(cold_sum)"

  out="$(run_prune_real "$S" --scrub-cold)"
  rc=$?
  lglob="$(sql_path "$S")/cold/cc-logs-*.parquet"
  tglob="$(sql_path "$S")/cold/cc-traces-*.parquet"
  assert_eq "scrub exits 0" "0" "$rc"
  assert_contains "scrub rewrites both dirty files" "$out" "action=scrubbed-cold scrubbed_files=2"
  assert_contains "scrub reports the clean file" "$out" "cold/${clean_logs##*/}: clean rows=1"
  assert_eq "clean cold file byte-identical" "$clean_sum" "$(cksum <"$clean_logs")"
  assert_eq "scrubbed logs file keeps its rows" "2" "$(dq "SELECT count(*) FROM read_parquet('$(sql_path "$dirty_logs")');")"
  assert_eq "cold span row kept" "1" "$(dq "SELECT count(*) FROM read_parquet('$tglob');")"
  assert_eq "prompt and prompt_text gone from cold logs" "0" "$(dq "SELECT count(*) FROM read_parquet('$lglob') WHERE CAST(log_attributes_raw AS VARCHAR) LIKE '%SECRET_PROMPT%';")"
  assert_eq "user_prompt body NULLed" "1" "$(dq "SELECT count(*) FROM read_parquet('$lglob') WHERE event_name='user_prompt' AND body IS NULL;")"
  assert_eq "other user_prompt attributes kept" "1" "$(dq "SELECT count(*) FROM read_parquet('$lglob') WHERE CAST(log_attributes_raw AS VARCHAR) LIKE '%\"prompt_length\"%';")"
  assert_eq "structure attributes kept" "2" "$(dq "SELECT count(*) FROM read_parquet('$lglob') WHERE CAST(log_attributes_raw AS VARCHAR) LIKE '%\"tool_use_id\"%';")"
  assert_eq "prompt content gone from cold spans" "0" "$(dq "SELECT count(*) FROM read_parquet('$tglob') WHERE CAST(span_attributes_raw AS VARCHAR) LIKE '%SECRET_PROMPT%' OR user_prompt IS NOT NULL;")"
  assert_eq "scrub leaks no temps" "" "$(find "$S/cold" -name '*.tmp')"
  assert_eq "scrub releases the sentinel" "no" "$([[ -e "$S/.prune-in-progress" ]] && echo yes || echo no)"
  out="$(run_prune_real "$S" --dry-run)"
  assert_not_contains "no notice once cold is clean" "$out" "notice:"
  out="$(run_prune_real "$S" --scrub-cold)"
  assert_contains "second scrub finds nothing" "$out" "action=scrubbed-cold scrubbed_files=0"
else
  skip_case "duckdb not found — skipping --scrub-cold case"
fi

# --- 30. cold scan: one duckdb call per glob, clean marker skips it, keep-on compaction voids it ---
if [[ "$HAS_DUCKDB" == true ]]; then
  S="$(new_store coldmarker)"
  marker="$S/cold/.prompt-scrub-clean"
  # PATH wrapper counting duckdb invocations.
  WRAP="$TMP/duckdb-wrap"
  mkdir -p "$WRAP"
  printf '#!/usr/bin/env bash\nprintf x >>"%s"\nexec "%s" "$@"\n' "$TMP/duckdb-calls" "$(command -v duckdb)" >"$WRAP/duckdb"
  chmod +x "$WRAP/duckdb"
  duckdb_calls() { if [[ -f "$TMP/duckdb-calls" ]]; then wc -c <"$TMP/duckdb-calls" | tr -d ' \r'; else printf 0; fi; }

  real_log_line "$OLD" tool_decision claude_code.tool_decision "$TOOL_EXTRA" >"$S/cc-logs.json"
  real_trace_line "$OLD" claude_code.tool "" >"$S/cc-traces.json"
  run_prune_real "$S" >/dev/null
  assert_eq "clean scan under the lock writes the marker" "yes" "$([[ -e "$marker" ]] && echo yes || echo no)"
  real_log_line "$OLD" tool_decision claude_code.tool_decision "$TOOL_EXTRA" >"$S/cc-logs.json"
  run_prune_real "$S" >/dev/null
  real_log_line "$OLD" tool_decision claude_code.tool_decision "$TOOL_EXTRA" >"$S/cc-logs.json"
  run_prune_real "$S" >/dev/null
  assert_eq "keep-off compaction keeps the marker" "yes" "$([[ -e "$marker" ]] && echo yes || echo no)"
  assert_eq "three cold logs files" "3" "$(find "$S/cold" -name 'cc-logs-*.parquet' | wc -l | tr -d ' ')"

  rm -f "$marker" "$TMP/duckdb-calls"
  out="$(PATH="$WRAP:$PATH" run_prune_real "$S" --dry-run)"
  assert_eq "notice scan is one duckdb call per glob" "2" "$(duckdb_calls)"
  assert_not_contains "clean cold prints no notice" "$out" "notice:"
  assert_eq "dry-run writes no marker" "no" "$([[ -e "$marker" ]] && echo yes || echo no)"
  : >"$marker"
  rm -f "$TMP/duckdb-calls"
  PATH="$WRAP:$PATH" run_prune_real "$S" --dry-run >/dev/null
  assert_eq "marker skips the notice scan" "0" "$(duckdb_calls)"

  real_log_line "$OLD" user_prompt claude_code.user_prompt "$PROMPT_EXTRA" >"$S/cc-logs.json"
  CC_OTEL_COLD_KEEP_USER_PROMPTS=1 run_prune_real "$S" >/dev/null
  assert_eq "keep-on compaction removes the marker" "no" "$([[ -e "$marker" ]] && echo yes || echo no)"
  out="$(run_prune_real "$S" --dry-run)"
  assert_contains "notice returns once the marker is gone" "$out" "notice: 1 cold file(s)"

  : >"$marker"
  rm -f "$TMP/duckdb-calls"
  out="$(PATH="$WRAP:$PATH" run_prune_real "$S" --scrub-cold --dry-run)"
  assert_contains "scrub dry-run ignores the marker" "$out" "action=dry-run-scrub-cold affected_files=1"
  assert_eq "scrub discovery is one duckdb call per glob" "2" "$(duckdb_calls)"
  rm -f "$marker"
  out="$(run_prune_real "$S" --scrub-cold)"
  assert_contains "scrub rewrites the dirty file" "$out" "action=scrubbed-cold scrubbed_files=1"
  assert_eq "completed scrub writes the marker" "yes" "$([[ -e "$marker" ]] && echo yes || echo no)"

  # No-op path (nothing aged out): a clean scan still writes the marker under a brief sentinel.
  rm -f "$marker"
  real_log_line "$RECENT" tool_decision claude_code.tool_decision "$TOOL_EXTRA" >"$S/cc-logs.json"
  : >"$S/cc-traces.json"
  out="$(run_prune_real "$S")"
  rc=$?
  assert_eq "no-op run exits 0" "0" "$rc"
  assert_contains "no-op run takes the no-op path" "$out" "action=noop-nothing-to-prune"
  assert_eq "no-op run writes the marker" "yes" "$([[ -e "$marker" ]] && echo yes || echo no)"
  assert_eq "no-op run releases the sentinel" "no" "$([[ -e "$S/.prune-in-progress" ]] && echo yes || echo no)"
  rm -f "$TMP/duckdb-calls"
  PATH="$WRAP:$PATH" run_prune_real "$S" >/dev/null
  assert_eq "next no-op run makes no duckdb call" "0" "$(duckdb_calls)"
  rm -f "$marker"
  mkdir "$S/.prune-in-progress"
  out="$(run_prune_real "$S")"
  rc=$?
  assert_eq "held sentinel: no-op run exits 0" "0" "$rc"
  assert_contains "held sentinel: still the no-op path" "$out" "action=noop-nothing-to-prune"
  assert_not_contains "held sentinel: no error" "$out" "prune-otel-store.sh:"
  assert_eq "held sentinel: no marker" "no" "$([[ -e "$marker" ]] && echo yes || echo no)"
  assert_eq "held sentinel left in place" "yes" "$([[ -d "$S/.prune-in-progress" ]] && echo yes || echo no)"
  rmdir "$S/.prune-in-progress"
else
  skip_case "duckdb not found — skipping cold marker case"
fi

printf '\n%d passed, %d failed\n' "$((CASE_NUM - FAILED))" "$FAILED"
[[ "$FAILED" -eq 0 ]]
