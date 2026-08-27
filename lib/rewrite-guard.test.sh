#!/usr/bin/env bash
# Unit tests for the content-mutation disclosure guard. Tests source the
# canonical lib/rewrite-guard.sh directly and drive its contract in isolation;
# each plugin's own <plugin>.test.sh keeps the black-box hook contract tests.
# Because CI enforces that every plugin copy is byte-identical to the source,
# passing here covers the copies too.

set -uo pipefail

LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

PASS=0
FAIL=0
fail() {
  echo "FAIL: $*" >&2
  FAIL=$((FAIL + 1))
}
ok() {
  echo "ok: $*"
  PASS=$((PASS + 1))
}

# Every case runs against an isolated TMPDIR so "the scratch area is empty"
# is a real assertion about THIS guard's snapshots, not ambient temp noise.
WORK=$(mktemp -d "${TMPDIR:-/tmp}/rewrite-guard-test-XXXXXX")
trap 'rm -rf "$WORK"' EXIT
export TMPDIR="$WORK/tmp"
mkdir -p "$TMPDIR"

scratch_count() {
  find "$TMPDIR" -type f 2>/dev/null | wc -l | tr -d '[:space:]'
}

# --- Source the libs under test ----------------------------------------------
# shellcheck source=hook-utils.sh
source "$LIB_DIR/hook-utils.sh"
# shellcheck source=rewrite-guard.sh
source "$LIB_DIR/rewrite-guard.sh"

target="$WORK/target.txt"

# --- begin snapshots into TMPDIR (non-vacuity probe for every count below) ---
printf 'one\n' >"$target"
hook::rewrite_guard_begin "$target"
if [[ "$(scratch_count)" == "1" ]]; then
  ok "begin creates exactly one snapshot in TMPDIR"
else
  fail "begin: expected 1 snapshot in TMPDIR, found $(scratch_count)"
fi

# --- unchanged file: empty message, snapshot released ------------------------
hook::rewrite_take_disclosure "$target" "msg-unchanged"
if [[ -z "$HOOK_REWRITE_MESSAGE" ]]; then
  ok "take on unchanged file yields empty message"
else
  fail "take on unchanged file yielded '$HOOK_REWRITE_MESSAGE'"
fi
if [[ "$(scratch_count)" == "0" ]]; then
  ok "take releases the snapshot (unchanged path)"
else
  fail "take left $(scratch_count) file(s) behind (unchanged path)"
fi

# --- changed file: message set, snapshot released ----------------------------
hook::rewrite_guard_begin "$target"
printf 'two\n' >"$target"
hook::rewrite_take_disclosure "$target" "msg-changed"
if [[ "$HOOK_REWRITE_MESSAGE" == "msg-changed" ]]; then
  ok "take on changed file yields the message"
else
  fail "take on changed file yielded '$HOOK_REWRITE_MESSAGE'"
fi
if [[ "$(scratch_count)" == "0" ]]; then
  ok "take releases the snapshot (changed path)"
else
  fail "take left $(scratch_count) file(s) behind (changed path)"
fi

# --- destructive read: a second take resets the message ----------------------
hook::rewrite_take_disclosure "$target" "msg-again"
if [[ -z "$HOOK_REWRITE_MESSAGE" ]]; then
  ok "second take resets the message (destructive read)"
else
  fail "second take yielded '$HOOK_REWRITE_MESSAGE'"
fi

# --- exit without take: the EXIT trap releases the snapshot ------------------
# The #3401/#3405 leak class: an arm that exits without releasing. Run in a
# child bash so the exit is real.
printf 'three\n' >"$target"
bash -c '
  source "$1/hook-utils.sh"
  source "$1/rewrite-guard.sh"
  hook::rewrite_guard_begin "$2"
  exit 0
' _ "$LIB_DIR" "$target"
if [[ "$(scratch_count)" == "0" ]]; then
  ok "exit without take leaks no snapshot (EXIT trap)"
else
  fail "exit without take left $(scratch_count) file(s) behind"
fi

# ...including an arm that exits non-zero mid-flight.
bash -c '
  source "$1/hook-utils.sh"
  source "$1/rewrite-guard.sh"
  hook::rewrite_guard_begin "$2"
  exit 4
' _ "$LIB_DIR" "$target"
if [[ "$(scratch_count)" == "0" ]]; then
  ok "non-zero exit without take leaks no snapshot"
else
  fail "non-zero exit left $(scratch_count) file(s) behind"
fi

# --- snapshot failure: no orphan, guard inert --------------------------------
# The hand-rolled copies emptied their variable when cp failed but left the
# mktemp file behind; the guard removes it.
hook::rewrite_guard_begin "$WORK/does-not-exist"
if [[ "$(scratch_count)" == "0" ]]; then
  ok "failed snapshot leaves no orphan mktemp file"
else
  fail "failed snapshot left $(scratch_count) file(s) behind"
fi
printf 'four\n' >"$target"
hook::rewrite_take_disclosure "$target" "msg-inert"
if [[ -z "$HOOK_REWRITE_MESSAGE" ]]; then
  ok "take after failed snapshot yields empty message (inert guard)"
else
  fail "take after failed snapshot yielded '$HOOK_REWRITE_MESSAGE'"
fi

# --- disclose emits one systemMessage-only document on change ----------------
hook::rewrite_guard_begin "$target"
printf 'five\n' >"$target"
out=$(hook::rewrite_disclose PostToolUse "$target" "disclose-msg")
if command -v jq >/dev/null 2>&1; then
  if [[ "$(printf '%s' "$out" | jq -s 'length')" == "1" ]] &&
    [[ "$(printf '%s' "$out" | jq -r '.systemMessage')" == "disclose-msg" ]] &&
    [[ "$(printf '%s' "$out" | jq 'has("hookSpecificOutput")')" == "false" ]]; then
    ok "disclose emits one systemMessage-only document"
  else
    fail "disclose output malformed: $out"
  fi
else
  if [[ "$out" == *disclose-msg* ]]; then
    ok "disclose emits the message (jq absent; string check)"
  else
    fail "disclose emitted nothing"
  fi
fi

# --- disclose emits nothing when unchanged -----------------------------------
hook::rewrite_guard_begin "$target"
out=$(hook::rewrite_disclose PostToolUse "$target" "should-not-appear")
if [[ -z "$out" ]]; then
  ok "disclose emits nothing on an unchanged file"
else
  fail "disclose emitted on an unchanged file: $out"
fi

# --- take composes with emit_channels as ONE document ------------------------
# The #3406 class: rewrite disclosure plus findings context must be one JSON
# document carrying both channels.
hook::rewrite_guard_begin "$target"
printf 'six\n' >"$target"
hook::rewrite_take_disclosure "$target" "compose-msg"
out=$(hook::emit_channels PostToolUse "some findings" "$HOOK_REWRITE_MESSAGE")
if command -v jq >/dev/null 2>&1; then
  if [[ "$(printf '%s' "$out" | jq -s 'length')" == "1" ]] &&
    [[ "$(printf '%s' "$out" | jq -r '.systemMessage')" == "compose-msg" ]] &&
    [[ "$(printf '%s' "$out" | jq -r '.hookSpecificOutput.additionalContext')" == "some findings" ]]; then
    ok "take + emit_channels compose both channels into one document"
  else
    fail "composed output malformed: $out"
  fi
else
  ok "compose check skipped (jq absent)"
fi

echo
echo "rewrite-guard tests: $PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]]
