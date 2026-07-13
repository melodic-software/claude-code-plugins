#!/usr/bin/env bash
# Contract test for hook-telemetry-sink.sh (claude-ops plugin). Black-box.
# The sink reads one envelope on stdin and appends one hook-events.jsonl line.
set -uo pipefail

HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SINK="$HOOK_DIR/hook-telemetry-sink.sh"
TEST_TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TEST_TMPDIR"' EXIT

# shellcheck source=claude-ops-test-helpers.sh
source "$HOOK_DIR/claude-ops-test-helpers.sh"

envelope() {
  # <hook> <hook_event> <status> <duration_ms> <subject> <tool>
  jq -nc \
    --arg hook "$1" --arg ev "$2" --arg st "$3" \
    --argjson dur "$4" --arg subj "$5" --arg tool "$6" \
    '{schema_version:"1.0", timestamp:"2026-07-12T00:00:00Z",
      hook:$hook, hook_event:$ev, status:$st, duration_ms:$dur,
      data:{subject:$subj, tool:$tool}}'
}

run_sink() {
  local proj="$1" line="$2"
  printf '%s\n' "$line" | env CLAUDE_PROJECT_DIR="$proj" bash "$SINK" >/dev/null 2>&1
}

# --- ok → status success, exit_code 0, field mapping -----------------------
P="$TEST_TMPDIR/p1"; mkdir -p "$P"
run_sink "$P" "$(envelope config-change-audit ConfigChange ok 4 project_settings '')"
LOG="$P/.claude/observability/hook-events.jsonl"
if [[ -s "$LOG" ]]; then
  assert_eq "ts mapped from timestamp" "2026-07-12T00:00:00Z" "$(jq -r '.ts' "$LOG")"
  assert_eq "event from hook_event" "ConfigChange" "$(jq -r '.event' "$LOG")"
  assert_eq "hook mapped" "config-change-audit" "$(jq -r '.hook' "$LOG")"
  assert_eq "duration_ms mapped" "4" "$(jq -r '.duration_ms' "$LOG")"
  assert_eq "subject from data" "project_settings" "$(jq -r '.subject' "$LOG")"
  assert_eq "ok → status success" "success" "$(jq -r '.status' "$LOG")"
  assert_eq "ok → exit_code 0" "0" "$(jq -r '.exit_code' "$LOG")"
else
  bad "sink wrote no line for ok envelope"
fi

# --- error → status error, exit_code 2 -------------------------------------
P2="$TEST_TMPDIR/p2"; mkdir -p "$P2"
run_sink "$P2" "$(envelope tool-failure-audit PostToolUseFailure error 5 Bash:dotnet Bash)"
LOG2="$P2/.claude/observability/hook-events.jsonl"
assert_eq "error → status error" "error" "$(jq -r '.status' "$LOG2")"
assert_eq "error → exit_code 2" "2" "$(jq -r '.exit_code' "$LOG2")"
assert_eq "tool mapped from data" "Bash" "$(jq -r '.tool' "$LOG2")"

# --- blocked → status blocked preserved, exit_code 2 -----------------------
P3="$TEST_TMPDIR/p3"; mkdir -p "$P3"
run_sink "$P3" "$(envelope permission-denied-audit PermissionDenied blocked 5 Bash:git Bash)"
LOG3="$P3/.claude/observability/hook-events.jsonl"
assert_eq "blocked → status blocked" "blocked" "$(jq -r '.status' "$LOG3")"
assert_eq "blocked → exit_code 2" "2" "$(jq -r '.exit_code' "$LOG3")"

# --- Malformed / empty stdin → no crash, no line ---------------------------
P4="$TEST_TMPDIR/p4"; mkdir -p "$P4"
printf 'not json\n' | env CLAUDE_PROJECT_DIR="$P4" bash "$SINK" >/dev/null 2>&1
RC=$?
assert_exit "malformed stdin → exit 0" 0 "$RC"
assert_file_absent "malformed stdin → no line" "$P4/.claude/observability/hook-events.jsonl"

printf '' | env CLAUDE_PROJECT_DIR="$P4" bash "$SINK" >/dev/null 2>&1
assert_exit "empty stdin → exit 0" 0 "$?"

# --- Missing required envelope key → dropped -------------------------------
P5="$TEST_TMPDIR/p5"; mkdir -p "$P5"
printf '%s\n' '{"schema_version":"1.0","hook":"x"}' | env CLAUDE_PROJECT_DIR="$P5" bash "$SINK" >/dev/null 2>&1
assert_file_absent "incomplete envelope → no line" "$P5/.claude/observability/hook-events.jsonl"

report
