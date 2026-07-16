#!/usr/bin/env bash
# Tests for lib/json.sh.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=json.sh
source "$SCRIPT_DIR/json.sh"
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../tests/lib.sh"

OUT="$(printf 'line1\r\nline2\r\n' | wit_strip_cr)"
assert_eq "CR stripped" "$(printf 'line1\nline2\n')" "$OUT"
assert_not_contains "no CR remains" "$OUT" "$(printf '\r')"

assert_eq "schema version constant" "1.0" "$WIT_SCHEMA_VERSION"

[[ $FAILED -eq 0 ]] || exit 1
