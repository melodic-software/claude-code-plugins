# shellcheck shell=bash
# Shared assertion primitives for this skill's *.test.sh suites. Sourced, not
# executed; the *.test.sh glob a runner selects on never picks this file up.
#
# Each suite owns its own FAILED / CASE_NUM counters and sets them before
# sourcing this file. PASS lines go to stdout, FAIL lines to stderr, and the
# suite prints its own summary and exits non-zero when FAILED is above 0.
#
# Param order: (label, expected, actual) for assert_eq / assert_exit,
# (label, haystack, needle) for the substring assertions.
#
# Duplicated per plugin by design, not drift; see
# docs/conventions/shell-test-helpers/README.md at the repo root.

pass() {
  CASE_NUM=$((CASE_NUM + 1))
  printf 'PASS: %s\n' "$1"
}
fail() {
  CASE_NUM=$((CASE_NUM + 1))
  FAILED=$((FAILED + 1))
  printf 'FAIL: %s\n  detail: %s\n' "$1" "$2" >&2
}
assert_eq() {
  if [[ "$2" == "$3" ]]; then pass "$1"; else fail "$1" "expected: $2, actual: $3"; fi
}
assert_exit() {
  if [[ "$2" == "$3" ]]; then pass "$1"; else fail "$1" "expected exit $2, got $3"; fi
}
assert_contains() {
  case "$2" in
  *"$3"*) pass "$1" ;;
  *) fail "$1" "expected to contain: $3" ;;
  esac
}
assert_not_contains() {
  case "$2" in
  *"$3"*) fail "$1" "unexpected substring: $3" ;;
  *) pass "$1" ;;
  esac
}
