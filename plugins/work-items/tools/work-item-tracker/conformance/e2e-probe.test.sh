#!/usr/bin/env bash
# shellcheck disable=SC2154  # FAILED/CASE_NUM initialized by the sourced lib
set -uo pipefail

S="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/e2e-probe.sh"
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../tests/lib.sh"

out="$(bash "$S" --help 2>/dev/null)"
assert_eq "--help exit 0" "0" "$?"
assert_contains "--help mentions lifecycle" "$out" "lifecycle"

bash "$S" --nope >/dev/null 2>&1
assert_eq "unknown flag → usage exit 2" "2" "$?"

# Regression guard: the probe must exercise the wayfind labels' declared,
# colon-SPACE form (`wayfind: research` / `wayfind: task` — Labels.cs and
# /planning:wayfind both require it verbatim) and never regress to the
# colon-no-space form (`wayfind:research` / `wayfind:task`), which a probe run
# would silently create in the sandbox without ever exercising a label value
# containing a space. The forbidden needles are built, not written literally,
# so this file itself never contains the very string it bans.
SRC="$(cat "$S")"
WAYFIND_PREFIX="wayfind:"
assert_contains "probe creates wayfind: research (space)" "$SRC" "${WAYFIND_PREFIX} research"
assert_contains "probe creates wayfind: task (space)" "$SRC" "${WAYFIND_PREFIX} task"
assert_not_contains "probe never regresses to wayfind:research (no space)" "$SRC" "${WAYFIND_PREFIX}research"
assert_not_contains "probe never regresses to wayfind:task (no space)" "$SRC" "${WAYFIND_PREFIX}task"

[[ $FAILED -eq 0 ]] || exit 1
