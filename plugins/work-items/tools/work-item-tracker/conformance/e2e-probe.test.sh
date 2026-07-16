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

[[ $FAILED -eq 0 ]] || exit 1
