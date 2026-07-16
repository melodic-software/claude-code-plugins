#!/usr/bin/env bash
# Contract test for the start-collector PUBLIC FACADE.
# The facade is a thin exec pass-through to the private otel/ backend; the
# backend's own behavior is tested in otel/start-collector.test.sh. This test
# asserts only the facade contract: --help passes through (rc 0, non-empty) and
# the body delegates to the co-located otel/ backend.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FACADE="$SCRIPT_DIR/start-collector.sh"

# Inline test helpers — self-contained, no external test lib (ships with the plugin).
FAILED=0
CASE_NUM=0
pass() { CASE_NUM=$((CASE_NUM + 1)); printf 'PASS: [%d] %s\n' "$CASE_NUM" "$1"; }
fail() {
  CASE_NUM=$((CASE_NUM + 1))
  printf 'FAIL: [%d] %s — expected %q got %q\n' "$CASE_NUM" "$1" "$2" "$3" >&2
  FAILED=$((FAILED + 1))
}
skip_case() { printf 'SKIP: %s\n' "$1" >&2; }
assert_eq() { if [[ "$3" == "$2" ]]; then pass "$1"; else fail "$1" "$2" "$3"; fi; }
assert_exit() { if [[ "$3" == "$2" ]]; then pass "$1"; else fail "$1" "exit $2" "exit $3"; fi; }
assert_contains() { if [[ "$2" == *"$3"* ]]; then pass "$1"; else fail "$1" "contains: $3" "$2"; fi; }
assert_not_contains() { if [[ "$2" != *"$3"* ]]; then pass "$1"; else fail "$1" "absent: $3" "$2"; fi; }
assert_file_exists() { if [[ -f "$2" ]]; then pass "$1"; else fail "$1" "file exists: $2" "absent"; fi; }

# --help passes through to the backend (rc 0, non-empty usage text).
help_out=$(bash "$FACADE" --help 2>&1)
rc=$?
assert_exit "facade --help exits 0" 0 "$rc"
assert_contains "facade --help delegates to backend usage" "$help_out" "start-collector.sh"

# Structural: the facade delegates to the private otel/ backend body.
# shellcheck disable=SC2016  # asserting the literal source text — $ must not expand
assert_contains "facade execs otel/ backend" "$(cat "$FACADE")" 'exec bash "$_SCRIPT_DIR/../otel/$(basename "$0")"'

[[ ${FAILED:-0} -eq 0 ]] || exit 1
