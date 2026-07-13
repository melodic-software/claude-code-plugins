#!/usr/bin/env bash
# Contract test for pre-compact-audit.sh (claude-ops plugin). Black-box.
set -uo pipefail

HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="$HOOK_DIR/pre-compact-audit.sh"
TEST_TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TEST_TMPDIR"' EXIT

# shellcheck source=claude-ops-test-helpers.sh
source "$HOOK_DIR/claude-ops-test-helpers.sh"
unset CLAUDE_PROJECT_DIR

INPUT='{"trigger":"auto"}'

TEL="$TEST_TMPDIR/tel.json"
SINK="$(make_sink "$TEL")"
env HOOK_TELEMETRY_SINK="$SINK" bash "$HOOK" <<<"$INPUT" >/dev/null 2>&1
if wait_for_sink "$TEL"; then
  assert_eq "hook id" "pre-compact-audit" "$(jq -r '.hook' "$TEL")"
  assert_eq "hook_event" "PreCompact" "$(jq -r '.hook_event' "$TEL")"
  assert_eq "status" "ok" "$(jq -r '.status' "$TEL")"
  assert_eq "data.subject" "auto" "$(jq -r '.data.subject' "$TEL")"
else
  bad "no envelope written when sink wired"
fi

OUT=$(bash "$HOOK" <<<"$INPUT" 2>&1); RC=$?
assert_exit "unwired → exit 0" 0 "$RC"
assert_silent "unwired → silent" "$OUT"

TELK="$TEST_TMPDIR/telk.json"; SINKK="$(make_sink "$TELK")"
env HOOK_TELEMETRY_SINK="$SINKK" HOOK_PRE_COMPACT_AUDIT_ENABLED=false \
  bash "$HOOK" <<<"$INPUT" >/dev/null 2>&1
assert_file_absent "kill switch → no envelope" "$TELK"

TELM="$TEST_TMPDIR/telm.json"; SINKM="$(make_sink "$TELM")"
env HOOK_TELEMETRY_SINK="$SINKM" bash "$HOOK" <<<'{}' >/dev/null 2>&1
assert_file_absent "missing trigger → no envelope" "$TELM"

report
