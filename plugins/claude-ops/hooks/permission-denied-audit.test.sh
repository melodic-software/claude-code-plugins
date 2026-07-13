#!/usr/bin/env bash
# Contract test for permission-denied-audit.sh (claude-ops plugin). Black-box.
set -uo pipefail

HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="$HOOK_DIR/permission-denied-audit.sh"
TEST_TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TEST_TMPDIR"' EXIT

# shellcheck source=claude-ops-test-helpers.sh
source "$HOOK_DIR/claude-ops-test-helpers.sh"
unset CLAUDE_PROJECT_DIR

# --- Bash → first-token subject; raw command never captured ----------------
TEL="$TEST_TMPDIR/tel.json"
SINK="$(make_sink "$TEL")"
env HOOK_TELEMETRY_SINK="$SINK" \
  bash "$HOOK" <<<'{"tool_name":"Bash","tool_input":{"command":"git push --force origin main"}}' >/dev/null 2>&1
if wait_for_sink "$TEL"; then
  assert_eq "hook id" "permission-denied-audit" "$(jq -r '.hook' "$TEL")"
  assert_eq "hook_event" "PermissionDenied" "$(jq -r '.hook_event' "$TEL")"
  assert_eq "status" "blocked" "$(jq -r '.status' "$TEL")"
  assert_eq "data.subject" "Bash:git" "$(jq -r '.data.subject' "$TEL")"
  assert_eq "data.tool" "Bash" "$(jq -r '.data.tool' "$TEL")"
  assert_absent "raw command not captured" "$(cat "$TEL")" "--force"
else
  bad "no envelope written when sink wired"
fi

# --- Quoted env-assignment value must not leak into the subject ------------
TELQ="$TEST_TMPDIR/telq.json"; SINKQ="$(make_sink "$TELQ")"
env HOOK_TELEMETRY_SINK="$SINKQ" \
  bash "$HOOK" <<<'{"tool_name":"Bash","tool_input":{"command":"TOKEN=\"secret value\" curl https://x"}}' >/dev/null 2>&1
if wait_for_sink "$TELQ"; then
  assert_eq "quoted assignment → bare Bash subject" "Bash" "$(jq -r '.data.subject' "$TELQ")"
  assert_absent "no value fragment leaked" "$(cat "$TELQ")" "secret"
  assert_absent "no value fragment leaked (2)" "$(cat "$TELQ")" "value"
else
  bad "no envelope written for quoted-assignment command"
fi

# --- Non-Bash tool → tool name as subject ----------------------------------
TELW="$TEST_TMPDIR/telw.json"; SINKW="$(make_sink "$TELW")"
env HOOK_TELEMETRY_SINK="$SINKW" \
  bash "$HOOK" <<<'{"tool_name":"Write","tool_input":{"file_path":"secret.env"}}' >/dev/null 2>&1
if wait_for_sink "$TELW"; then
  assert_eq "Write subject = tool name" "Write" "$(jq -r '.data.subject' "$TELW")"
  assert_absent "file_path not captured" "$(cat "$TELW")" "secret.env"
else
  bad "no envelope written for Write"
fi

OUT=$(bash "$HOOK" <<<'{"tool_name":"Bash","tool_input":{"command":"ls"}}' 2>&1); RC=$?
assert_exit "unwired → exit 0" 0 "$RC"
assert_silent "unwired → silent" "$OUT"

TELK="$TEST_TMPDIR/telk.json"; SINKK="$(make_sink "$TELK")"
env HOOK_TELEMETRY_SINK="$SINKK" HOOK_PERMISSION_DENIED_AUDIT_ENABLED=false \
  bash "$HOOK" <<<'{"tool_name":"Bash","tool_input":{"command":"ls"}}' >/dev/null 2>&1
assert_file_absent "kill switch → no envelope" "$TELK"

report
