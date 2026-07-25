# shellcheck shell=bash
# Self-contained assertion library for the work-item-tracker seam's *.test.sh
# files. The seam ships with its own harness so its tests run unchanged wherever
# the seam is resolved from — the plugin's bundled copy or a consumer-vendored
# copy — with no dependency on the host repo's test tooling.
#
# Source it from any seam test, CWD-independent, relative to the test's own
# location (never via git toplevel — the host repo is not the seam's repo):
#   source "$SCRIPT_DIR/../tests/lib.sh"
#
# Each test file owns its own FAILED and CASE_NUM counters; helpers increment
# them in the caller's scope. PASS lines go to stdout, FAIL lines to stderr.
# Test files exit non-zero at the end:  [[ $FAILED -eq 0 ]] || exit 1
#
# Param order: subject (actual) BEFORE expected — reads as "in <subject>,
# expect <something>".
#
# Duplicated across plugins by design, not drift — see
# docs/conventions/shell-test-helpers/README.md at the repo root.

[[ -n "${_WIT_TESTS_LIB_LOADED:-}" ]] && return 0
readonly _WIT_TESTS_LIB_LOADED=1

# Strip any inherited git-hook context so a test that builds a git fixture can
# never resolve to the real repo instead of its throwaway dir (a git hook chain
# exports GIT_DIR / GIT_INDEX_FILE etc.; leaving them set has rewritten a real
# repo's refs in the past). Every seam test gets a clean git environment.
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_PREFIX GIT_OBJECT_DIRECTORY

# Defensive counter defaults so the first assertion in a test that forgot to
# declare them does not trip `set -u`.
: "${FAILED:=0}"
: "${CASE_NUM:=0}"

# pass <label> — print a PASS line, increment CASE_NUM. No exit.
pass() {
  CASE_NUM=$((CASE_NUM + 1))
  printf 'PASS: [%d] %s\n' "$CASE_NUM" "$1"
}

# fail <label> <expected> <actual> — print a FAIL line to stderr, increment
# FAILED + CASE_NUM. No exit (run-all-cases discipline; the final check exits).
fail() {
  CASE_NUM=$((CASE_NUM + 1))
  printf 'FAIL: [%d] %s — expected %q got %q\n' \
    "$CASE_NUM" "$1" "$2" "$3" >&2
  FAILED=$((FAILED + 1))
}

# skip_suite <reason> — print a SKIP marker and exit 0. Use when a test cannot
# run ANY of its cases (missing toolchain, wrong platform).
skip_suite() {
  printf 'SKIP: %s\n' "$1" >&2
  exit 0
}

# assert_eq <label> <expected> <actual> — exact match.
assert_eq() {
  local label="$1" expected="$2" actual="$3"
  if [[ "$actual" == "$expected" ]]; then
    pass "$label"
  else
    fail "$label" "$expected" "$actual"
  fi
}

# assert_contains <label> <haystack> <needle> — substring match.
assert_contains() {
  CASE_NUM=$((CASE_NUM + 1))
  local label="$1" haystack="$2" needle="$3"
  if [[ "$haystack" == *"$needle"* ]]; then
    printf 'PASS: [%d] %s\n' "$CASE_NUM" "$label"
  else
    printf 'FAIL: [%d] %s — expected %q in: %s\n' \
      "$CASE_NUM" "$label" "$needle" "$haystack" >&2
    FAILED=$((FAILED + 1))
  fi
}

# assert_not_contains <label> <haystack> <needle> — substring absence.
assert_not_contains() {
  CASE_NUM=$((CASE_NUM + 1))
  local label="$1" haystack="$2" needle="$3"
  if [[ "$haystack" != *"$needle"* ]]; then
    printf 'PASS: [%d] %s\n' "$CASE_NUM" "$label"
  else
    printf 'FAIL: [%d] %s — forbidden %q present in: %s\n' \
      "$CASE_NUM" "$label" "$needle" "$haystack" >&2
    FAILED=$((FAILED + 1))
  fi
}
