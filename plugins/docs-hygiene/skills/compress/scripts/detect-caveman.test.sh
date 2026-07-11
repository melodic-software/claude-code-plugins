#!/usr/bin/env bash
# Contract test for detect-caveman.sh (the /compress backend detector).
#
# Self-contained: no shared assertion lib; resolves the script under test
# relative to this file. Asserts the always-exit-0 contract, both output
# labels, and graceful degradation to "unknown" when claude/jq are absent.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DETECT="$SCRIPT_DIR/detect-caveman.sh"

PASS=0
FAIL=0
ok() {
  echo "ok: $*"
  PASS=$((PASS + 1))
}
fail() {
  echo "FAIL: $*" >&2
  FAIL=$((FAIL + 1))
}

assert_exit0() {
  local label="$1"
  shift
  if "$@" >/dev/null 2>&1; then
    ok "$label"
  else
    fail "$label (non-zero exit)"
  fi
}

assert_contains() {
  local label="$1" haystack="$2" needle="$3"
  if [[ "$haystack" == *"$needle"* ]]; then
    ok "$label"
  else
    fail "$label (missing: $needle)"
  fi
}

assert_exit0 "--help exits 0" bash "$DETECT" --help
assert_exit0 "-h exits 0" bash "$DETECT" -h
assert_exit0 "bare invocation exits 0" bash "$DETECT"

help_out="$(bash "$DETECT" --help 2>/dev/null)"
assert_contains "--help prints usage" "$help_out" "Usage:"

out="$(bash "$DETECT" 2>/dev/null)"
assert_contains "backend label present" "$out" "Caveman backend:"
assert_contains "plugin id label present" "$out" "Caveman plugin id:"

# Degradation contract: without claude/jq on PATH the script must report
# "unknown" (and still exit 0) rather than fail. Resolve bash first so the
# empty PATH only affects lookups inside the script under test.
BASH_BIN="$(command -v bash)"
if out_nopath="$(PATH="" "$BASH_BIN" "$DETECT" 2>/dev/null)"; then
  ok "empty-PATH invocation exits 0"
else
  fail "empty-PATH invocation exits 0 (non-zero exit)"
fi
assert_contains "degrades to unknown without claude/jq" "$out_nopath" "Caveman backend: unknown"
assert_contains "plugin id none without claude/jq" "$out_nopath" "Caveman plugin id: none"

echo
if [[ $FAIL -ne 0 ]]; then
  echo "$FAIL check(s) failed." >&2
  exit 1
fi
echo "OK: detect-caveman.sh tests passed ($PASS checks)"
