#!/usr/bin/env bash
# shellcheck disable=SC2154  # FAILED/CASE_NUM initialized by the sourced lib
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
S="$SCRIPT_DIR/e2e-probe.sh"
source "$SCRIPT_DIR/../tests/lib.sh"

out="$(bash "$S" --help 2>/dev/null)"
assert_eq "--help exit 0" "0" "$?"
assert_contains "--help mentions lifecycle" "$out" "lifecycle"

bash "$S" --nope >/dev/null 2>&1
assert_eq "unknown flag → usage exit 2" "2" "$?"

# The probe must use the wayfind labels' colon-SPACE form, never the no-space form a
# run would silently create. The banned needles are built, so this file never holds them.
SRC="$(cat "$S")"
WAYFIND_PREFIX="wayfind:"
assert_contains "probe creates wayfind: research (space)" "$SRC" "${WAYFIND_PREFIX} research"
assert_contains "probe creates wayfind: task (space)" "$SRC" "${WAYFIND_PREFIX} task"
assert_not_contains "probe never regresses to wayfind:research (no space)" "$SRC" "${WAYFIND_PREFIX}research"
assert_not_contains "probe never regresses to wayfind:task (no space)" "$SRC" "${WAYFIND_PREFIX}task"

[[ $FAILED -eq 0 ]] || exit 1
