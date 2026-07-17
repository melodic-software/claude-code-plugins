#!/usr/bin/env bash
# Regression tests for /observability skill jq pipelines + privacy filter.
# Validates the queries in context/data-sources.md and rules in context/privacy.md
# against synthetic JSONL fixtures.

set -uo pipefail

TEST_TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TEST_TMPDIR"' EXIT

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

# --- Fixture: hook-events.jsonl ---
HOOK_LOG="$TEST_TMPDIR/hook-events.jsonl"
SINCE_ISO="2026-01-01T00:00:00Z"

# Append a single event to $HOOK_LOG. Schema mirrors observability/conventions.md fields;
# session_id/branch/cwd are constant across the fixture (no test asserts on them).
# Args: <ts> <hook> <tool> <duration_ms> <exit_code> <subject> <status>
emit_event() {
  jq -nc \
    --arg ts "$1" --arg hook "$2" --arg tool "$3" \
    --argjson duration_ms "$4" --argjson exit_code "$5" \
    --arg subject "$6" --arg status "$7" \
    '{ts:$ts, event:"PostToolUse", hook:$hook, tool:$tool,
      duration_ms:$duration_ms, exit_code:$exit_code,
      subject:$subject, status:$status,
      session_id:"s1", branch:"main", cwd:"/repo"}' \
    >>"$HOOK_LOG"
}

# Count lines in a JSONL fixture, stripping spaces and Git Bash CR.
lines_in() {
  wc -l <"$1" | tr -d ' \r'
}

# 12 bash-format events: 10 fast (~120ms), 2 slow (5000ms+ outliers)
for i in $(seq 1 10); do
  emit_event "2026-04-29T10:0${i}:00.000Z" bash-format Write 120 0 test.sh success
done
emit_event "2026-04-29T10:11:00.000Z" bash-format Write 5000 0 slow.sh success
emit_event "2026-04-29T10:12:00.000Z" bash-format Write 6000 0 slower.sh success

# 5 sarif-diagnostics events with 1 error
for i in $(seq 1 4); do
  emit_event "2026-04-29T11:0${i}:00.000Z" sarif-diagnostics Edit 800 0 a.cs success
done
emit_event "2026-04-29T11:05:00.000Z" sarif-diagnostics Edit 1200 2 b.cs error

# Out-of-window event (should be filtered)
emit_event "2025-01-01T00:00:00.000Z" old-hook Write 100 0 old.sh success

# --- Test 1: latency p50/p95 per (hook,event) ---
LAT_OUT=$(jq -s --arg since "$SINCE_ISO" '
  map(select(.ts >= $since))
  | group_by(.hook + "|" + .event)
  | map({
      key: (.[0].hook + " " + .[0].event),
      n: length,
      p50: (sort_by(.duration_ms) | .[length/2|floor].duration_ms),
      p95: (sort_by(.duration_ms) | .[(length*0.95)|floor].duration_ms),
      max: (max_by(.duration_ms).duration_ms)
    })' "$HOOK_LOG")

assert_contains "bash-format key present" "$LAT_OUT" "bash-format PostToolUse"
assert_contains "sarif-diagnostics key present" "$LAT_OUT" "sarif-diagnostics PostToolUse"

bash_format_n=$(echo "$LAT_OUT" | jq -r '.[] | select(.key=="bash-format PostToolUse") | .n')
assert_eq "bash-format count = 12" "12" "$bash_format_n"

bash_format_max=$(echo "$LAT_OUT" | jq -r '.[] | select(.key=="bash-format PostToolUse") | .max')
assert_eq "bash-format max = 6000" "6000" "$bash_format_max"

# --- Test 2: error rate per hook ---
ERR_OUT=$(jq -s --arg since "$SINCE_ISO" '
  map(select(.ts >= $since))
  | group_by(.hook)
  | map({
      hook: .[0].hook,
      n: length,
      errors: (map(select(.exit_code != 0)) | length)
    })
  | map(select(.errors > 0))' "$HOOK_LOG")

assert_contains "sarif-diagnostics has errors" "$ERR_OUT" "sarif-diagnostics"
sarif_err=$(echo "$ERR_OUT" | jq -r '.[] | select(.hook=="sarif-diagnostics") | .errors')
assert_eq "sarif error count = 1" "1" "$sarif_err"

# --- Test 3: window filter excludes 2025 event ---
filtered_count=$(jq -s --arg since "$SINCE_ISO" \
  'map(select(.ts >= $since)) | length' "$HOOK_LOG")
assert_eq "window filter applied" "17" "$filtered_count" # 12 + 5 (excludes old-hook)

assert_not_contains "out-of-window event excluded" "$LAT_OUT" "old-hook"

# --- Test 4: redaction — token-shaped strings ---
redact() {
  sed -E 's|[A-Za-z0-9+/_-]{32,}={0,2}|[redacted-token]|g'
}

# Synthetic 40-char base64-shaped string (clearly fake — XYZ prefix + repeating chars)
fake_token='XYZAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA1234'
token_input="some_field=${fake_token}"
redacted=$(echo "$token_input" | redact)
assert_contains "long base64-shaped string redacted" "$redacted" "[redacted-token]"
assert_not_contains "raw fake token absent" "$redacted" "$fake_token"

# --- Test 5: redaction — env-var assignment ---
env_redact() {
  sed -E 's/(AWS_[A-Z_]*|GITHUB_[A-Z_]*|.*_TOKEN|.*_KEY|.*_SECRET|.*_PASSWORD)=[^[:space:]"]*/\1=[redacted]/gi'
}

env_input='subject contains GITHUB_TOKEN=placeholder123 in error log' # gitleaks:allow — synthetic fixture proving this very value gets redacted
env_redacted=$(echo "$env_input" | env_redact)
assert_contains "GITHUB_TOKEN redacted" "$env_redacted" "GITHUB_TOKEN=[redacted]"
assert_not_contains "raw value absent" "$env_redacted" "placeholder123"

# --- Test 6: paths are NOT redacted (normal paths must survive) ---
path_input='subject=apps/monolith-api/Program.cs'
path_after=$(echo "$path_input" | env_redact)
assert_contains "path preserved through env filter" "$path_after" "apps/monolith-api/Program.cs"

# --- Test 7: empty-log graceful degradation ---
EMPTY_LOG="$TEST_TMPDIR/empty.jsonl"
: >"$EMPTY_LOG"
empty_out=$(jq -s --arg since "$SINCE_ISO" \
  'map(select(.ts >= $since)) | length' "$EMPTY_LOG")
assert_eq "empty log returns 0" "0" "$empty_out"

# --- Test 8: missing-log handled by caller guard ---
MISSING_LOG="$TEST_TMPDIR/does-not-exist.jsonl"
if [[ -f "$MISSING_LOG" ]]; then
  count=$(jq -s 'length' "$MISSING_LOG")
else
  count=0
fi
assert_eq "missing log handled by guard" "0" "$count"

# --- Test 9: clean action — synthetic mixed-age data + dry-run + real run ---
CLEAN="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/scripts/clean.sh"
clean_test_dir="$TEST_TMPDIR/clean-test"
mkdir -p "$clean_test_dir"
(cd "$clean_test_dir" && git init -q && git config commit.gpgsign false)
mkdir -p "$clean_test_dir/.claude/observability"
TODAY=$(date -u +%Y-%m-%dT%H:%M:%SZ)
if date -u -d "45 days ago" +%s >/dev/null 2>&1; then
  OLD_45=$(date -u -d "45 days ago" +%Y-%m-%dT%H:%M:%SZ)
  OLD_5=$(date -u -d "5 days ago" +%Y-%m-%dT%H:%M:%SZ)
else
  OLD_45=$(date -u -v-45d +%Y-%m-%dT%H:%M:%SZ)
  OLD_5=$(date -u -v-5d +%Y-%m-%dT%H:%M:%SZ)
fi
HOOK_FX="$clean_test_dir/.claude/observability/hook-events.jsonl"
for _ in 1 2 3; do
  printf '{"ts":"%s","event":"Test","hook":"x","duration_ms":0,"exit_code":0,"subject":"a","status":"success"}\n' "$OLD_45" >>"$HOOK_FX"
done
for _ in 1 2; do
  printf '{"ts":"%s","event":"Test","hook":"x","duration_ms":0,"exit_code":0,"subject":"a","status":"success"}\n' "$OLD_5" >>"$HOOK_FX"
done
for _ in 1 2; do
  printf '{"ts":"%s","event":"Test","hook":"x","duration_ms":0,"exit_code":0,"subject":"a","status":"success"}\n' "$TODAY" >>"$HOOK_FX"
done

# 9a: dry-run does not modify
before_hook=$(lines_in "$HOOK_FX")
(cd "$clean_test_dir" && bash "$CLEAN" --keep-days 30 --dry-run --quiet) >/dev/null 2>&1
after_hook=$(lines_in "$HOOK_FX")
assert_eq "clean --dry-run preserves hook log" "$before_hook" "$after_hook"

# 9b: real run with --keep-days 30 prunes 45-day-old (3 hook)
(cd "$clean_test_dir" && bash "$CLEAN" --keep-days 30 --quiet) >/dev/null 2>&1
after_hook=$(lines_in "$HOOK_FX")
assert_eq "clean prunes 45-day-old hook events" "4" "$after_hook" # 2 (5d) + 2 (today)

# 9c: --keep-days 4 prunes the 5-day-old hook events (2)
(cd "$clean_test_dir" && bash "$CLEAN" --keep-days 4 --quiet) >/dev/null 2>&1
after_hook=$(lines_in "$HOOK_FX")
assert_eq "clean --keep-days 4 prunes 5-day-old" "2" "$after_hook" # only today's 2 remain

# 9d: idempotent — re-run with same window changes nothing
(cd "$clean_test_dir" && bash "$CLEAN" --keep-days 4 --quiet) >/dev/null 2>&1
after_hook2=$(lines_in "$HOOK_FX")
assert_eq "clean is idempotent" "$after_hook" "$after_hook2"

# 9e: missing files don't crash
empty_dir="$TEST_TMPDIR/empty-clean"
mkdir -p "$empty_dir"
(cd "$empty_dir" && git init -q && git config commit.gpgsign false)
mkdir -p "$empty_dir/.claude/observability"
rc=0
(cd "$empty_dir" && bash "$CLEAN" --keep-days 30 --quiet) >/dev/null 2>&1 || rc=$?
assert_eq "clean handles missing files (exit 0)" "0" "$rc"

# 9f: invalid --keep-days rejected
rc=0
(cd "$clean_test_dir" && bash "$CLEAN" --keep-days notanumber --quiet) >/dev/null 2>&1 || rc=$?
assert_eq "clean rejects non-integer --keep-days (exit 2)" "2" "$rc"

# 9g: OTEL store wiring — clean delegates to otel/prune-otel-store.sh (dry-run, non-destructive).
# env -u CC_OTEL_STORE forces the store to resolve to the temp repo regardless of any
# machine-level CC_OTEL_STORE.
mkdir -p "$clean_test_dir/.claude/observability/otel"
otel_now=$EPOCHSECONDS
otel_logs="$clean_test_dir/.claude/observability/otel/cc-logs.json"
printf '{"resourceLogs":[{"scopeLogs":[{"logRecords":[{"timeUnixNano":"%s"}]}]}]}\n' "$((otel_now - 3600))000000000" >"$otel_logs"
printf '{"resourceLogs":[{"scopeLogs":[{"logRecords":[{"timeUnixNano":"%s"}]}]}]}\n' "$((otel_now - 30 * 86400))000000000" >>"$otel_logs"
otel_before=$(lines_in "$otel_logs")
otel_out=$(cd "$clean_test_dir" && env -u CC_OTEL_STORE bash "$CLEAN" --keep-days 30 --dry-run 2>&1)
assert_contains "clean wires OTEL prune (dry-run report)" "$otel_out" "cc-logs.json: kept=1 dropped=1"
otel_after=$(lines_in "$otel_logs")
assert_eq "clean --dry-run leaves OTEL store unchanged" "$otel_before" "$otel_after"

# --- Test 10: failed-then-fixed sequence detection (data-sources.md query) ---
retry_log="$TEST_TMPDIR/retry-events.jsonl"
printf '%s\n' \
  '{"ts":"2026-01-01T10:00:00Z","hook":"bash-format","exit_code":1}' \
  '{"ts":"2026-01-01T10:00:05Z","hook":"bash-format","exit_code":0}' \
  '{"ts":"2026-01-01T10:01:00Z","hook":"biome","exit_code":0}' \
  '{"ts":"2026-01-01T10:02:00Z","hook":"bash-format","exit_code":1}' \
  '{"ts":"2026-01-01T10:02:05Z","hook":"bash-format","exit_code":0}' >"$retry_log"
retry_out=$(jq -s '
  sort_by(.ts) as $e
  | [range(1; $e | length)
     | select($e[. - 1].hook == $e[.].hook and $e[. - 1].exit_code != 0 and $e[.].exit_code == 0)
     | $e[. - 1].hook]
  | group_by(.) | map({hook: .[0], retries: length})
  | sort_by(-.retries)
' "$retry_log")
assert_eq "failed-then-fixed counts bash-format retries" \
  "$(echo '[{"hook":"bash-format","retries":2}]' | jq -c .)" "$(echo "$retry_out" | jq -c .)"

# --- Summary ---
TOTAL=$CASE_NUM
PASSED=$((TOTAL - FAILED))
printf '\n--- Results: %d/%d passed ---\n' "$PASSED" "$TOTAL"
[[ $FAILED -eq 0 ]] || exit 1
