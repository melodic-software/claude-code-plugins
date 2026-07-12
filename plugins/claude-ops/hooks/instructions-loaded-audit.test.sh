#!/usr/bin/env bash
# Contract test for instructions-loaded-audit.sh (claude-ops plugin). Black-box.
set -uo pipefail

HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="$HOOK_DIR/instructions-loaded-audit.sh"
TEST_TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TEST_TMPDIR"' EXIT

# shellcheck source=claude-ops-test-helpers.sh
source "$HOOK_DIR/claude-ops-test-helpers.sh"
unset CLAUDE_PROJECT_DIR

INPUT='{"file_path":".claude/rules/x.md","load_reason":"path_glob_match"}'

# --- Emits the "<file>:<reason>" subject -----------------------------------
TEL="$TEST_TMPDIR/tel.json"
SINK="$(make_sink "$TEL")"
env HOOK_TELEMETRY_SINK="$SINK" bash "$HOOK" <<<"$INPUT" >/dev/null 2>&1
if wait_for_sink "$TEL"; then
  assert_eq "hook id" "instructions-loaded-audit" "$(jq -r '.hook' "$TEL")"
  assert_eq "hook_event" "InstructionsLoaded" "$(jq -r '.hook_event' "$TEL")"
  assert_eq "status" "ok" "$(jq -r '.status' "$TEL")"
  assert_eq "data.subject" ".claude/rules/x.md:path_glob_match" "$(jq -r '.data.subject' "$TEL")"
else
  bad "no envelope written when sink wired"
fi

# --- session_start is filtered out by default ------------------------------
TELS="$TEST_TMPDIR/tels.json"; SINKS="$(make_sink "$TELS")"
env HOOK_TELEMETRY_SINK="$SINKS" \
  bash "$HOOK" <<<'{"file_path":"CLAUDE.md","load_reason":"session_start"}' >/dev/null 2>&1
assert_file_absent "session_start filtered by default" "$TELS"

# --- session_start opt-in re-enables emission ------------------------------
TELO="$TEST_TMPDIR/telo.json"; SINKO="$(make_sink "$TELO")"
env HOOK_TELEMETRY_SINK="$SINKO" HOOK_INSTRUCTIONS_LOADED_AUDIT_LOG_SESSION_START=true \
  bash "$HOOK" <<<'{"file_path":"CLAUDE.md","load_reason":"session_start"}' >/dev/null 2>&1
if wait_for_sink "$TELO"; then
  assert_eq "session_start opt-in subject" "CLAUDE.md:session_start" "$(jq -r '.data.subject' "$TELO")"
else
  bad "session_start opt-in did not emit"
fi

OUT=$(bash "$HOOK" <<<"$INPUT" 2>&1); RC=$?
assert_exit "unwired → exit 0" 0 "$RC"
assert_silent "unwired → silent" "$OUT"

TELK="$TEST_TMPDIR/telk.json"; SINKK="$(make_sink "$TELK")"
env HOOK_TELEMETRY_SINK="$SINKK" HOOK_INSTRUCTIONS_LOADED_AUDIT_ENABLED=false \
  bash "$HOOK" <<<"$INPUT" >/dev/null 2>&1
assert_file_absent "kill switch → no envelope" "$TELK"

report
