#!/usr/bin/env bash
# Contract test for hook-failure-audit.sh (claude-ops plugin). Black-box.
#
# The fixture failure record is a structural copy of a REAL transcript
# attachment from the #1416/#2577 incident host (session ac1c95e3, 2026-08-13):
# a disk-hygiene destructive-guard registration resolving `bash` to the Windows
# WSL relay and dying at launch. The two false-positive shapes asserted below
# (a `hook_success` quoting an error in stdout, and a message record quoting a
# failure record as a string) are the exact traps hit while mining the incident
# transcripts — see #2577.
set -uo pipefail

HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="$HOOK_DIR/hook-failure-audit.sh"
TEST_TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TEST_TMPDIR"' EXIT

# shellcheck source=claude-ops-test-helpers.sh
source "$HOOK_DIR/claude-ops-test-helpers.sh"
unset CLAUDE_PROJECT_DIR

WSL_STDERR='Failed with non-blocking status code: <3>WSL (10 - Relay) ERROR: CreateProcessCommon:818: execvpe(/bin/bash) failed: No such file or directory'

# One transcript line per record, matching the real attachment envelope shape.
failure_record() { # <hookName> <command>
  printf '{"parentUuid":"p","isSidechain":false,"attachment":{"type":"hook_non_blocking_error","hookName":"%s","toolUseID":"toolu_x","hookEvent":"PreToolUse","stderr":"%s","stdout":"","exitCode":1,"command":"%s","durationMs":2080},"type":"attachment","uuid":"u","timestamp":"2026-08-13T13:56:38.155Z","session_id":"s","sessionId":"s","version":"2.1.228"}\n' \
    "$1" "${WSL_STDERR//\"/\\\"}" "$2"
}

make_transcript() { # <path> — base fixture: 1 real failure + both false-positive shapes
  local t="$1"
  {
    # Truncated first line, as a bounded tail read would produce.
    printf 'garbage-not-json {"half": \n'
    failure_record "PreToolUse:Bash" "bash \${CLAUDE_PLUGIN_ROOT}/hooks/run-python-hook.sh"
    # FALSE POSITIVE 1: a hook_success whose stdout QUOTES the failure text.
    printf '{"attachment":{"type":"hook_success","hookName":"PostToolUse:Edit","stdout":"saw hook_non_blocking_error and %s in a log","stderr":"","exitCode":0},"type":"attachment","uuid":"u2","session_id":"s"}\n' "${WSL_STDERR//\"/\\\"}"
    # FALSE POSITIVE 2: an assistant message quoting a failure record as a STRING.
    printf '{"type":"assistant","message":{"content":[{"type":"text","text":"sample: {\\"type\\": \\"hook_non_blocking_error\\", \\"hookName\\": \\"PreToolUse:QuotedOnly\\"}"}]},"uuid":"u3","session_id":"s"}\n'
  } >"$t"
}

# Execute the script DIRECTLY, the way the hooks.json registration invokes it
# (no `bash` prefix) — so a non-executable committed mode fails here the same
# way it would fail in production (exit 126) instead of being masked by an
# explicit interpreter.
run_hook() { # <transcript> <data_dir> [extra env pairs...]
  local transcript="$1" data_dir="$2"
  shift 2
  env CLAUDE_PLUGIN_DATA="$data_dir" "$@" "$HOOK" <<<"{\"session_id\":\"test-session\",\"transcript_path\":\"$transcript\",\"hook_event_name\":\"Stop\"}" 2>&1
}

# --- Red-first core: a real launch-failure record is surfaced ---------------
T1="$TEST_TMPDIR/t1.jsonl"
make_transcript "$T1"
DATA1="$TEST_TMPDIR/data1"
OUT=$(run_hook "$T1" "$DATA1")
RC=$?
assert_exit "failure surfaced -> exit 0" 0 "$RC"
assert_contains "names the dead hook" "$OUT" "PreToolUse:Bash"
assert_contains "systemMessage emitted" "$OUT" "systemMessage"
assert_contains "explains fail-open" "$OUT" "fail-open"
assert_contains "stale-session guidance" "$OUT" "restart"

# --- Structural matching: neither false-positive shape fires ----------------
assert_absent "hook_success quoting an error does not fire" "$OUT" "PostToolUse:Edit"
assert_absent "string-quoted record does not fire" "$OUT" "PreToolUse:QuotedOnly"

# --- Once per session per hook: second run is silent ------------------------
OUT2=$(run_hook "$T1" "$DATA1")
RC2=$?
assert_exit "dedup run -> exit 0" 0 "$RC2"
assert_silent "same failures already warned -> silent" "$OUT2"

# --- A NEW failing hook re-warns, already-warned hooks stay muted -----------
failure_record "SessionStart" "node missing-lifecycle-hook.mjs" >>"$T1"
OUT3=$(run_hook "$T1" "$DATA1")
assert_contains "new failing hook warned" "$OUT3" "SessionStart"
assert_absent "already-warned hook muted" "$OUT3" "PreToolUse:Bash"

# --- Distinct registrations sharing a hookName are distinct failures --------
# Multiple plugins register on the same event+matcher (e.g. several
# PreToolUse:Bash guards); the attachment's command is what tells them apart.
# A second registration failing later in the session must re-warn even though
# the first already wrote this hookName to the marker.
failure_record "PreToolUse:Bash" "other-plugin-guard.sh --different-registration" >>"$T1"
OUT3B=$(run_hook "$T1" "$DATA1")
assert_contains "same hookName, new registration -> re-warns" "$OUT3B" "other-plugin-guard.sh"
OUT3C=$(run_hook "$T1" "$DATA1")
assert_silent "both registrations warned -> silent" "$OUT3C"

# --- No CLAUDE_PLUGIN_DATA: degrade toward re-warning, never silence --------
T2="$TEST_TMPDIR/t2.jsonl"
make_transcript "$T2"
OUT4=$(env -u CLAUDE_PLUGIN_DATA bash "$HOOK" <<<"{\"session_id\":\"test-session\",\"transcript_path\":\"$T2\",\"hook_event_name\":\"Stop\"}" 2>&1)
assert_contains "no marker home -> still warns" "$OUT4" "PreToolUse:Bash"
OUT5=$(env -u CLAUDE_PLUGIN_DATA bash "$HOOK" <<<"{\"session_id\":\"test-session\",\"transcript_path\":\"$T2\",\"hook_event_name\":\"Stop\"}" 2>&1)
assert_contains "no marker home -> re-warns rather than suppresses" "$OUT5" "PreToolUse:Bash"

# --- Bounded tail: a failure pushed past the window is not read -------------
T3="$TEST_TMPDIR/t3.jsonl"
DATA3="$TEST_TMPDIR/data3"
{
  failure_record "PreToolUse:OutOfWindow" "cmd-a"
  # Pad well past the small test cap so the record above falls outside it.
  for _ in $(seq 1 200); do
    printf '{"type":"assistant","message":{"content":[{"type":"text","text":"%s"}]},"uuid":"pad","session_id":"s"}\n' \
      "pad-pad-pad-pad-pad-pad-pad-pad-pad-pad-pad-pad-pad-pad-pad-pad-pad-pad"
  done
  failure_record "PreToolUse:InWindow" "cmd-b"
} >"$T3"
OUT6=$(run_hook "$T3" "$DATA3" HOOK_FAILURE_AUDIT_TAIL_BYTES=8000)
assert_contains "in-window failure reported" "$OUT6" "PreToolUse:InWindow"
assert_absent "out-of-window failure not read" "$OUT6" "PreToolUse:OutOfWindow"

# --- Kill switch -------------------------------------------------------------
OUT7=$(run_hook "$T2" "$TEST_TMPDIR/data-kill" CLAUDE_PLUGIN_OPTION_HOOK_FAILURE_AUDIT_ENABLED=false)
RC7=$?
assert_exit "kill switch -> exit 0" 0 "$RC7"
assert_silent "kill switch -> silent" "$OUT7"

# --- Missing / absent transcript: silent allow -------------------------------
OUT8=$(env CLAUDE_PLUGIN_DATA="$TEST_TMPDIR/data-miss" bash "$HOOK" <<<'{"session_id":"s","hook_event_name":"Stop"}' 2>&1)
RC8=$?
assert_exit "no transcript_path -> exit 0" 0 "$RC8"
assert_silent "no transcript_path -> silent" "$OUT8"
OUT9=$(env CLAUDE_PLUGIN_DATA="$TEST_TMPDIR/data-gone" bash "$HOOK" <<<"{\"session_id\":\"s\",\"transcript_path\":\"$TEST_TMPDIR/nope.jsonl\",\"hook_event_name\":\"Stop\"}" 2>&1)
RC9=$?
assert_exit "nonexistent transcript -> exit 0" 0 "$RC9"
assert_silent "nonexistent transcript -> silent" "$OUT9"

# --- Clean transcript: silent ------------------------------------------------
T4="$TEST_TMPDIR/t4.jsonl"
printf '{"type":"assistant","message":{"content":[{"type":"text","text":"all fine"}]},"uuid":"c","session_id":"s"}\n' >"$T4"
OUT10=$(run_hook "$T4" "$TEST_TMPDIR/data-clean")
RC10=$?
assert_exit "clean transcript -> exit 0" 0 "$RC10"
assert_silent "clean transcript -> silent" "$OUT10"

# --- Telemetry envelope when a sink is wired ---------------------------------
T5="$TEST_TMPDIR/t5.jsonl"
make_transcript "$T5"
TEL="$TEST_TMPDIR/tel.json"
SINK="$(make_sink "$TEL")"
env CLAUDE_PLUGIN_DATA="$TEST_TMPDIR/data-tel" HOOK_TELEMETRY_SINK="$SINK" \
  bash "$HOOK" <<<"{\"session_id\":\"tel-session\",\"transcript_path\":\"$T5\",\"hook_event_name\":\"Stop\"}" >/dev/null 2>&1
if wait_for_sink "$TEL"; then
  assert_eq "hook id" "hook-failure-audit" "$(jq -r '.hook' "$TEL")"
  assert_eq "hook_event" "Stop" "$(jq -r '.hook_event' "$TEL")"
  assert_eq "status" "error" "$(jq -r '.status' "$TEL")"
  assert_eq "subject is the hook name (privacy-safe)" "PreToolUse:Bash" "$(jq -r '.data.subjects[0]' "$TEL")"
  assert_eq "total failure count" "1" "$(jq -r '.data.total' "$TEL")"
else
  bad "no envelope written when sink wired"
fi

report
