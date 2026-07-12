#!/usr/bin/env bash
# Tests for preflight.sh
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/test-helpers.sh
source "$SCRIPT_DIR/lib/test-helpers.sh"

PREFLIGHT="$SCRIPT_DIR/preflight.sh"
FAILED=0

rc=0
bash "$PREFLIGHT" --help >/dev/null 2>&1 || rc=$?
assert_exit "--help exits 0" 0 "$rc"

out="$(bash "$PREFLIGHT" 2>/dev/null)"
code=$?
assert_exit "always exits 0" 0 "$code"
assert_contains "RUNTIME_PROCS label" "$out" "RUNTIME_PROCS:"
assert_contains "RECENT_BUILD label" "$out" "RECENT_BUILD:"
assert_contains "IDE_OPEN label" "$out" "IDE_OPEN:"

if [[ $FAILED -ne 0 ]]; then
  echo "FAILED: $FAILED test(s)"
  exit 1
fi
echo "OK: preflight.sh tests passed"
