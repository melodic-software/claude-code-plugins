#!/usr/bin/env bash
# Contract test for instructions-loaded-audit.sh (claude-ops plugin). Black-box.
set -uo pipefail

HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="$HOOK_DIR/instructions-loaded-audit.sh"
TEST_TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TEST_TMPDIR"' EXIT

# shellcheck source=claude-ops-test-helpers.sh
source "$HOOK_DIR/claude-ops-test-helpers.sh"

# Real InstructionsLoaded payloads carry ABSOLUTE file paths; the hook must
# reduce them to a repo-relative path (or basename) so no absolute prefix /
# username leaks into the store. A non-git PROJ makes hook::repo_root return
# PROJ itself, so paths under it relativize deterministically.
PROJ="$TEST_TMPDIR/proj"
mkdir -p "$PROJ"
ABS="$PROJ/.claude/rules/x.md"
INPUT=$(MSYS_NO_PATHCONV=1 jq -nc --arg fp "$ABS" '{file_path:$fp, load_reason:"path_glob_match"}')

# --- Absolute path under the project → repo-relative subject ---------------
TEL="$TEST_TMPDIR/tel.json"
SINK="$(make_sink "$TEL")"
env HOOK_TELEMETRY_SINK="$SINK" CLAUDE_PROJECT_DIR="$PROJ" bash "$HOOK" <<<"$INPUT" >/dev/null 2>&1
if wait_for_sink "$TEL"; then
  assert_eq "hook id" "instructions-loaded-audit" "$(jq -r '.hook' "$TEL")"
  assert_eq "hook_event" "InstructionsLoaded" "$(jq -r '.hook_event' "$TEL")"
  assert_eq "status" "ok" "$(jq -r '.status' "$TEL")"
  assert_eq "repo-relative subject" ".claude/rules/x.md:path_glob_match" "$(jq -r '.data.subject' "$TEL")"
  assert_absent "no absolute prefix leaked" "$(cat "$TEL")" "$PROJ"
else
  bad "no envelope written when sink wired"
fi

# --- Path outside the project → basename only (no directory leak) ----------
# An absolute path that is NOT under the project root (a user-level instruction
# file). Built from TEST_TMPDIR so no machine-specific literal is committed.
TELB="$TEST_TMPDIR/telb.json"; SINKB="$(make_sink "$TELB")"
OUTSIDE="$TEST_TMPDIR/elsewhere/private-dir/CLAUDE.md"
env HOOK_TELEMETRY_SINK="$SINKB" CLAUDE_PROJECT_DIR="$PROJ" \
  bash "$HOOK" <<<"$(MSYS_NO_PATHCONV=1 jq -nc --arg fp "$OUTSIDE" '{file_path:$fp, load_reason:"include"}')" >/dev/null 2>&1
if wait_for_sink "$TELB"; then
  assert_eq "out-of-repo → basename subject" "CLAUDE.md:include" "$(jq -r '.data.subject' "$TELB")"
  assert_absent "no parent dir leaked" "$(cat "$TELB")" "private-dir"
else
  bad "no envelope written for out-of-repo path"
fi

# --- session_start is filtered out by default ------------------------------
TELS="$TEST_TMPDIR/tels.json"; SINKS="$(make_sink "$TELS")"
env HOOK_TELEMETRY_SINK="$SINKS" CLAUDE_PROJECT_DIR="$PROJ" \
  bash "$HOOK" <<<"$(MSYS_NO_PATHCONV=1 jq -nc --arg fp "$PROJ/CLAUDE.md" '{file_path:$fp, load_reason:"session_start"}')" >/dev/null 2>&1
assert_file_absent "session_start filtered by default" "$TELS"

# --- session_start opt-in re-enables emission ------------------------------
TELO="$TEST_TMPDIR/telo.json"; SINKO="$(make_sink "$TELO")"
env HOOK_TELEMETRY_SINK="$SINKO" CLAUDE_PROJECT_DIR="$PROJ" \
  HOOK_INSTRUCTIONS_LOADED_AUDIT_LOG_SESSION_START=true \
  bash "$HOOK" <<<"$(MSYS_NO_PATHCONV=1 jq -nc --arg fp "$PROJ/CLAUDE.md" '{file_path:$fp, load_reason:"session_start"}')" >/dev/null 2>&1
if wait_for_sink "$TELO"; then
  assert_eq "session_start opt-in subject" "CLAUDE.md:session_start" "$(jq -r '.data.subject' "$TELO")"
else
  bad "session_start opt-in did not emit"
fi

OUT=$(env CLAUDE_PROJECT_DIR="$PROJ" bash "$HOOK" <<<"$INPUT" 2>&1); RC=$?
assert_exit "unwired → exit 0" 0 "$RC"
assert_silent "unwired → silent" "$OUT"

TELK="$TEST_TMPDIR/telk.json"; SINKK="$(make_sink "$TELK")"
env HOOK_TELEMETRY_SINK="$SINKK" CLAUDE_PROJECT_DIR="$PROJ" HOOK_INSTRUCTIONS_LOADED_AUDIT_ENABLED=false \
  bash "$HOOK" <<<"$INPUT" >/dev/null 2>&1
assert_file_absent "kill switch → no envelope" "$TELK"

report
