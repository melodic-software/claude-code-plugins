#!/usr/bin/env bash
# test-scope: plugins/plugin-diagnostics/hooks/hook-failure-audit.sh
set -uo pipefail

HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEST_TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TEST_TMPDIR"' EXIT

# shellcheck source=plugin-diagnostics-test-helpers.sh
source "$HOOK_DIR/plugin-diagnostics-test-helpers.sh"

PROJ="$TEST_TMPDIR/proj"
mkdir -p "$PROJ"
DATA_DIR="$TEST_TMPDIR/data"
mkdir -p "$DATA_DIR"

TRANSCRIPT="$TEST_TMPDIR/transcript.jsonl"
printf '{"attachment":{"type":"hook_non_blocking_error","hookName":"PreToolUse:demo","toolUseID":"toolu_x","hookEvent":"PreToolUse","stderr":"boom","stdout":"","exitCode":1,"command":"bash demo.sh","durationMs":2},"type":"attachment","uuid":"u","session_id":"s"}\n' >"$TRANSCRIPT"
MEMBERS="\"transcript_path\":\"$TRANSCRIPT\",\"hook_event_name\":\"Stop\""

drive() {
  local payload="$1" capture_file="$2" sink
  : >"$capture_file"
  sink="$(make_sink "$capture_file")"
  env HOOK_TELEMETRY_SINK="$sink" CLAUDE_PROJECT_DIR="$PROJ" CLAUDE_PLUGIN_DATA="$DATA_DIR" \
    bash "$HOOK_DIR/hook-failure-audit.sh" <<<"$payload" >/dev/null 2>&1
}

hook="hook-failure-audit"
TEL="$TEST_TMPDIR/with.json"
drive "{\"session_id\":\"sess-$hook\",$MEMBERS}" "$TEL"
if wait_for_sink "$TEL"; then
  assert_eq "$hook: data.session_id carried" "sess-$hook" "$(jq -r '.data.session_id' "$TEL")"
else
  bad "$hook: no envelope captured with a session_id in the payload"
fi

TEL2="$TEST_TMPDIR/without.json"
drive "{$MEMBERS}" "$TEL2"
if wait_for_sink "$TEL2"; then
  assert_eq "$hook: no session_id → key absent from data" "false" "$(jq '.data | has("session_id")' "$TEL2")"
else
  bad "$hook: no envelope captured without a session_id"
fi

TEL3="$TEST_TMPDIR/hostile.json"
drive "{\"session_id\":\"../x\",$MEMBERS}" "$TEL3"
if wait_for_sink "$TEL3"; then
  assert_eq "$hook: a non-id session_id is not carried" "false" "$(jq '.data | has("session_id")' "$TEL3")"
else
  bad "$hook: no envelope captured with a hostile session_id"
fi

report
