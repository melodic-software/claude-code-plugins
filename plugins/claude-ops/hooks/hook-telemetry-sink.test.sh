#!/usr/bin/env bash
# Contract test for hook-telemetry-sink.sh (claude-ops plugin). Black-box.
# The sink reads one envelope on stdin and appends one line: to
# <root>/hook-events.jsonl (legacy shape) when the envelope carries no
# data.session_id, to <root>/sessions/<session_id>.jsonl (spine shape) when it
# does. <root> is .observability/claude under the project.
set -uo pipefail

HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SINK="$HOOK_DIR/hook-telemetry-sink.sh"
TEST_TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TEST_TMPDIR"' EXIT

# shellcheck source=claude-ops-test-helpers.sh
source "$HOOK_DIR/claude-ops-test-helpers.sh"

envelope() {
  # <hook> <hook_event> <status> <duration_ms> <subject> <tool> [<extra-data-members>]
  local extra="${7:-}"
  jq -nc \
    --arg hook "$1" --arg ev "$2" --arg st "$3" \
    --argjson dur "$4" --arg subj "$5" --arg tool "$6" \
    --argjson extra "{${extra}}" \
    '{schema_version:"1.0", timestamp:"2026-07-12T00:00:00Z",
      hook:$hook, hook_event:$ev, status:$st, duration_ms:$dur,
      data:({subject:$subj, tool:$tool} + $extra)}'
}

run_sink() {
  local proj="$1" line="$2"
  printf '%s\n' "$line" | env CLAUDE_PROJECT_DIR="$proj" bash "$SINK" >/dev/null 2>&1
}

ROOT_REL=".observability/claude"

# --- ok → status success, exit_code 0, field mapping (legacy route) ---------
P="$TEST_TMPDIR/p1"; mkdir -p "$P"
run_sink "$P" "$(envelope config-change-audit ConfigChange ok 4 project_settings '')"
LOG="$P/$ROOT_REL/hook-events.jsonl"
if [[ -s "$LOG" ]]; then
  assert_eq "ts mapped from timestamp" "2026-07-12T00:00:00Z" "$(jq -r '.ts' "$LOG")"
  assert_eq "event from hook_event" "ConfigChange" "$(jq -r '.event' "$LOG")"
  assert_eq "hook mapped" "config-change-audit" "$(jq -r '.hook' "$LOG")"
  assert_eq "duration_ms mapped" "4" "$(jq -r '.duration_ms' "$LOG")"
  assert_eq "subject from data" "project_settings" "$(jq -r '.subject' "$LOG")"
  assert_eq "ok → status success" "success" "$(jq -r '.status' "$LOG")"
  assert_eq "ok → exit_code 0" "0" "$(jq -r '.exit_code' "$LOG")"
else
  bad "sink wrote no line for ok envelope at $LOG"
fi
assert_file_absent "old .claude/observability path is no longer written" "$P/.claude/observability/hook-events.jsonl"

# --- error → status error, exit_code 2 -------------------------------------
P2="$TEST_TMPDIR/p2"; mkdir -p "$P2"
run_sink "$P2" "$(envelope tool-failure-audit PostToolUseFailure error 5 Bash:dotnet Bash)"
LOG2="$P2/$ROOT_REL/hook-events.jsonl"
assert_eq "error → status error" "error" "$(jq -r '.status' "$LOG2")"
assert_eq "error → exit_code 2" "2" "$(jq -r '.exit_code' "$LOG2")"
assert_eq "tool mapped from data" "Bash" "$(jq -r '.tool' "$LOG2")"

# --- blocked → status blocked preserved, exit_code 2 -----------------------
P3="$TEST_TMPDIR/p3"; mkdir -p "$P3"
run_sink "$P3" "$(envelope permission-denied-audit PermissionDenied blocked 5 Bash:git Bash)"
LOG3="$P3/$ROOT_REL/hook-events.jsonl"
assert_eq "blocked → status blocked" "blocked" "$(jq -r '.status' "$LOG3")"
assert_eq "blocked → exit_code 2" "2" "$(jq -r '.exit_code' "$LOG3")"

# --- Malformed / empty stdin → no crash, no line ---------------------------
P4="$TEST_TMPDIR/p4"; mkdir -p "$P4"
printf 'not json\n' | env CLAUDE_PROJECT_DIR="$P4" bash "$SINK" >/dev/null 2>&1
RC=$?
assert_exit "malformed stdin → exit 0" 0 "$RC"
assert_file_absent "malformed stdin → no line" "$P4/$ROOT_REL/hook-events.jsonl"

printf '' | env CLAUDE_PROJECT_DIR="$P4" bash "$SINK" >/dev/null 2>&1
assert_exit "empty stdin → exit 0" 0 "$?"

# --- Missing required envelope key → dropped -------------------------------
P5="$TEST_TMPDIR/p5"; mkdir -p "$P5"
printf '%s\n' '{"schema_version":"1.0","hook":"x"}' | env CLAUDE_PROJECT_DIR="$P5" bash "$SINK" >/dev/null 2>&1
assert_file_absent "incomplete envelope → no line" "$P5/$ROOT_REL/hook-events.jsonl"

# --- data.session_id routes the line per session, in the spine shape --------
P6="$TEST_TMPDIR/p6"; mkdir -p "$P6"
run_sink "$P6" "$(envelope api-error-audit StopFailure error 3 rate_limit '' '"session_id":"sess-42"')"
SLOG="$P6/$ROOT_REL/sessions/sess-42.jsonl"
if [[ -s "$SLOG" ]]; then
  jq -e 'has("session_id") and has("hook_event_name") and has("ts") and has("status") and has("source")' "$SLOG" >/dev/null 2>&1
  assert_exit "per-session line carries the full spine" 0 "$?"
  assert_eq "per-session: session_id" "sess-42" "$(jq -r .session_id "$SLOG")"
  assert_eq "per-session: hook_event_name from hook_event" "StopFailure" "$(jq -r .hook_event_name "$SLOG")"
  assert_eq "per-session: source is envelope" "envelope" "$(jq -r .source "$SLOG")"
  assert_eq "per-session: hook carried" "api-error-audit" "$(jq -r .hook "$SLOG")"
  assert_eq "per-session: duration carried" "3" "$(jq -r .duration_ms "$SLOG")"
  assert_eq "per-session: status mapped" "error" "$(jq -r .status "$SLOG")"
  assert_eq "per-session: exit_code derived" "2" "$(jq -r .exit_code "$SLOG")"
  assert_eq "per-session: no changed key when the producer sent none" "false" "$(jq 'has("changed")' "$SLOG")"
else
  bad "per-session route wrote nothing at $SLOG"
fi
assert_file_absent "per-session route writes no legacy line" "$P6/$ROOT_REL/hook-events.jsonl"

# --- data.changed is carried as a boolean when present ------------------------
run_sink "$P6" "$(envelope markdown-format PostToolUse ok 12 docs/a.md Write '"session_id":"sess-42","changed":true')"
assert_eq "changed: true carried" "true" "$(tail -1 "$SLOG" | jq -r .changed)"
run_sink "$P6" "$(envelope markdown-format PostToolUse ok 12 docs/a.md Write '"session_id":"sess-42","changed":false')"
assert_eq "changed: false carried" "false" "$(tail -1 "$SLOG" | jq -r .changed)"
assert_eq "three lines on the session file" 3 "$(wc -l <"$SLOG" | tr -d ' ')"

# --- a malformed session_id falls back to the legacy route ----------------------
P7="$TEST_TMPDIR/p7"; mkdir -p "$P7"
run_sink "$P7" "$(envelope api-error-audit StopFailure error 3 rate_limit '' '"session_id":"../escape"')"
assert_file_absent "hostile session_id → no session file" "$P7/$ROOT_REL/sessions"
assert_eq "hostile session_id → legacy line" 1 "$(wc -l <"$P7/$ROOT_REL/hook-events.jsonl" | tr -d ' ')"

# --- inside a checkout the root gets its self-ignoring guard; a changed guard refuses
P8="$TEST_TMPDIR/p8"; mkdir -p "$P8/.git"
run_sink "$P8" "$(envelope config-change-audit ConfigChange ok 4 project_settings '')"
assert_eq "checkout: guard healed" "*" "$(head -1 "$P8/$ROOT_REL/.gitignore")"
assert_eq "checkout: line written" 1 "$(wc -l <"$P8/$ROOT_REL/hook-events.jsonl" | tr -d ' ')"
P9="$TEST_TMPDIR/p9"; mkdir -p "$P9/.git" "$P9/$ROOT_REL"
printf 'sessions/\n' >"$P9/$ROOT_REL/.gitignore"
run_sink "$P9" "$(envelope config-change-audit ConfigChange ok 4 project_settings '')"
assert_file_absent "checkout with an operator's guard → refuses" "$P9/$ROOT_REL/hook-events.jsonl"
assert_file_absent "no checkout → no guard" "$P/$ROOT_REL/.gitignore"

# --- a configured root is honored; an uncontained one writes nothing ----------
P10="$TEST_TMPDIR/p10"; mkdir -p "$P10"
printf '%s\n' "$(envelope config-change-audit ConfigChange ok 4 x '')" |
  env CLAUDE_PROJECT_DIR="$P10" CLAUDE_PLUGIN_OPTION_SESSION_EVENT_LOG_DIR=telemetry/claude bash "$SINK" >/dev/null 2>&1
assert_eq "configured root honored" 1 "$(wc -l <"$P10/telemetry/claude/hook-events.jsonl" | tr -d ' ')"
printf '%s\n' "$(envelope config-change-audit ConfigChange ok 4 x '')" |
  env CLAUDE_PROJECT_DIR="$P10" CLAUDE_PLUGIN_OPTION_SESSION_EVENT_LOG_DIR=../up bash "$SINK" >/dev/null 2>&1
assert_file_absent "uncontained root writes nothing" "$TEST_TMPDIR/up"

report
