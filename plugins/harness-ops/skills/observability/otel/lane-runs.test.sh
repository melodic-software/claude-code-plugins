#!/usr/bin/env bash

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR

# shellcheck source=../../../lib/test-helpers.sh
source "$SCRIPT_DIR/../../../lib/test-helpers.sh"
fail() {
  CASE_NUM=$((CASE_NUM + 1))
  printf 'FAIL: [%d] %s — expected %q got %q\n' "$CASE_NUM" "$1" "$2" "$3" >&2
  FAILED=$((FAILED + 1))
}

if ! command -v duckdb >/dev/null 2>&1; then
  printf 'SKIP: duckdb not found — skipping lane-runs views\n' >&2
  exit 0
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

sql_path() {
  if command -v cygpath >/dev/null 2>&1; then cygpath -m "$1"; else printf '%s\n' "$1"; fi
}

SINK="$TMP/sink"
mkdir -p "$SINK"
INIT="$(sql_path "$SCRIPT_DIR/lane-runs.sql")"
q() {
  LANE_TRANSCRIPT_SINK="$(sql_path "$SINK")" duckdb -csv -noheader -init "$INIT" -c "$1" 2>/dev/null | tr -d '\r'
}

TRACE_A=33284f6935ab289df17507682acc6c66
TRACE_B=6231b3dd4912b8d706768f07c9843b10
cat >"$SINK/metrics.jsonl" <<EOF
{"run_id":42,"run_attempt":1,"job_id":"check-intent","lane":"pr-verify","created_at":"2026-11-02T10:00:00Z","date":"2026-11-02","outcome":"error","cache_read_input_tokens":300,"total_cost_usd":0.25,"model_usage":{"claude-opus-5-5":{"input_tokens":10}},"trace_id":"$TRACE_A","failure_class":"max-turns","failure_class_source":"lane-outcome","transcript":null}
{"run_id":18234567890,"run_attempt":2,"job_id":"review","lane":"pr-review-main","created_at":"2026-11-01T10:00:00Z","date":"2026-11-01","outcome":"success","transcript":null}
EOF
cat >"$SINK/outcomes.jsonl" <<EOF
{"run_id":42,"run_attempt":1,"trace_id":"$TRACE_A","check_run_id":9001,"job_name":"check-intent","lane":"pr-verify","workflow":"pr-verify","created_at":"2026-11-02T10:05:00Z","date":"2026-11-02","record":{"v":1,"lane":"pr-verify","outcome":"failure","class":"max-turns","handoff":true,"credential":{"secret":"CLAUDE_CODE_OAUTH_TOKEN","kind":"oauth-token"}}}
{"run_id":7,"run_attempt":1,"trace_id":"$TRACE_B-other","check_run_id":9002,"job_name":"x","lane":"pr-verify","workflow":"pr-verify","created_at":"2026-11-02T10:05:00Z","date":"2026-11-02","record":{"v":1,"lane":"pr-verify","outcome":"success","credential":{"secret":"CLAUDE_CODE_OAUTH_TOKEN","kind":"oauth-token"}}}
EOF

assert_eq "lane_runs reads both rows" "2" "$(q "SELECT count(*) FROM lane_runs;")"
assert_eq "new fields are typed" "300,0.25,BIGINT,DOUBLE" \
  "$(q "SELECT cache_read_input_tokens, total_cost_usd, typeof(cache_read_input_tokens), typeof(total_cost_usd) FROM lane_runs WHERE run_id = 42;")"
assert_eq "per-model usage reads as JSON" "10" "$(q "SELECT model_usage -> 'claude-opus-5-5' ->> 'input_tokens' FROM lane_runs WHERE run_id = 42;")"
assert_eq "an older row reads NULL for the fields it lacks" "true,true" \
  "$(q "SELECT total_cost_usd IS NULL, trace_id IS NULL FROM lane_runs WHERE run_id = 18234567890;")"
assert_eq "lane_outcomes lifts the record's outcome, class and handoff" "failure,max-turns,true,oauth-token" \
  "$(q "SELECT outcome, failure_class, handoff, credential_kind FROM lane_outcomes WHERE check_run_id = 9001;")"
assert_eq "a run joins its run attempt's records on trace_id, and only those" "42,9001" \
  "$(q "SELECT r.run_id, o.check_run_id FROM lane_runs r JOIN lane_outcomes o USING (trace_id);" | paste -sd'|')"

rm "$SINK/outcomes.jsonl"
assert_eq "lane_runs still loads when outcomes.jsonl does not exist yet" "2" "$(q "SELECT count(*) FROM lane_runs;")"

printf '\n%d passed, %d failed\n' "$((CASE_NUM - FAILED))" "$FAILED"
[[ "$FAILED" -eq 0 ]]
