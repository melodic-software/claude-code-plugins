#!/usr/bin/env bash
# Contract test for tool-failure-audit.sh (claude-ops plugin). Black-box.
set -uo pipefail

HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="$HOOK_DIR/tool-failure-audit.sh"
TEST_TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TEST_TMPDIR"' EXIT

# shellcheck source=claude-ops-test-helpers.sh
source "$HOOK_DIR/claude-ops-test-helpers.sh"
unset CLAUDE_PROJECT_DIR

# --- Bash → first-token subject; env/sudo prefixes stripped ----------------
TEL="$TEST_TMPDIR/tel.json"
SINK="$(make_sink "$TEL")"
env HOOK_TELEMETRY_SINK="$SINK" \
  bash "$HOOK" <<<'{"tool_name":"Bash","tool_input":{"command":"FOO=bar dotnet build"}}' >/dev/null 2>&1
if wait_for_sink "$TEL"; then
  assert_eq "hook id" "tool-failure-audit" "$(jq -r '.hook' "$TEL")"
  assert_eq "hook_event" "PostToolUseFailure" "$(jq -r '.hook_event' "$TEL")"
  assert_eq "status" "error" "$(jq -r '.status' "$TEL")"
  assert_eq "data.subject" "Bash:dotnet" "$(jq -r '.data.subject' "$TEL")"
  assert_eq "data.tool" "Bash" "$(jq -r '.data.tool' "$TEL")"
  assert_absent "raw command not captured" "$(cat "$TEL")" "build"
else
  bad "no envelope written when sink wired"
fi

# --- Write → tool name subject ---------------------------------------------
TELW="$TEST_TMPDIR/telw.json"; SINKW="$(make_sink "$TELW")"
env HOOK_TELEMETRY_SINK="$SINKW" \
  bash "$HOOK" <<<'{"tool_name":"Edit","tool_input":{"file_path":"a.cs"}}' >/dev/null 2>&1
if wait_for_sink "$TELW"; then
  assert_eq "Edit subject = tool name" "Edit" "$(jq -r '.data.subject' "$TELW")"
else
  bad "no envelope written for Edit"
fi

OUT=$(bash "$HOOK" <<<'{"tool_name":"Bash","tool_input":{"command":"ls"}}' 2>&1); RC=$?
assert_exit "unwired → exit 0" 0 "$RC"
assert_silent "unwired → silent" "$OUT"

TELK="$TEST_TMPDIR/telk.json"; SINKK="$(make_sink "$TELK")"
env HOOK_TELEMETRY_SINK="$SINKK" CLAUDE_PLUGIN_OPTION_TOOL_FAILURE_AUDIT_ENABLED=false \
  bash "$HOOK" <<<'{"tool_name":"Bash","tool_input":{"command":"ls"}}' >/dev/null 2>&1
assert_file_absent "kill switch → no envelope" "$TELK"

report
