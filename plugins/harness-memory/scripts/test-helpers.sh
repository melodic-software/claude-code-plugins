# shellcheck shell=bash
# test-helpers.sh: shared assertion primitives, the fixture-repo builder and the
# temp tree for this plugin's *.test.sh suites. Sourced, not executed; the test
# runner selects suites by the *.test.sh glob, so this file is never run.
#
# Sourcing creates TEST_TMPDIR, arms the EXIT trap that removes it, and
# initializes the FAILED / CASE_NUM counters each suite reports from. PASS lines
# go to stdout, FAIL lines to stderr. A suite ends with report_and_exit.
#
# Param order: (label, expected, actual) for assert_eq and assert_exit,
# (label, haystack, needle) for the containment assertions.
#
# Duplicated across plugins by design, not drift: see
# docs/conventions/shell-test-helpers/README.md at the repo root.

TEST_TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TEST_TMPDIR"' EXIT

FAILED=0
CASE_NUM=0

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

# Fixture git repos must never inherit an outer hook chain's exported git env,
# otherwise fixture commits mutate the REAL repo.
make_repo() {
  unset GIT_DIR GIT_INDEX_FILE GIT_WORK_TREE GIT_COMMON_DIR GIT_CONFIG
  mkdir -p "$1"
  (cd "$1" && git init -q && git config user.email "test@example.com" && git config user.name "test" && git commit -q --allow-empty -m init)
}

# Print the suite tally and exit: 0 when every check passed, 1 otherwise.
report_and_exit() {
  if [[ "$FAILED" -eq 0 ]]; then
    printf '\nAll %d checks passed.\n' "$CASE_NUM"
    exit 0
  fi
  printf '\n%d/%d checks failed.\n' "$FAILED" "$CASE_NUM" >&2
  exit 1
}
