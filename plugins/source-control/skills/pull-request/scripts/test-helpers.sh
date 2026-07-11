#!/usr/bin/env bash
# test-helpers.sh — shared assertion primitives for this plugin's *.test.sh
# suites. Self-contained — no host-repo assertion library. Sourced, not
# executed; the plugin test runner ignores it via the *.test.sh glob.
#
# Each test file owns its own FAILED / CASE_NUM counters (initialized here
# defensively). PASS lines go to stdout, FAIL lines to stderr. Test files
# exit non-zero at the end: [[ $FAILED -eq 0 ]] || exit 1
#
# Param order: subject (haystack/actual) BEFORE expected (needle), except
# assert_eq / assert_exit which take (label, expected, actual).

[[ -n "${_TESTS_LIB_LOADED:-}" ]] && return 0
readonly _TESTS_LIB_LOADED=1

# Strip inherited git-hook context so fixture `git init` / ref writes never
# resolve to the real repo when a test runs under a git hook chain.
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_PREFIX GIT_OBJECT_DIRECTORY

: "${FAILED:=0}"
: "${CASE_NUM:=0}"

# pass <label>
pass() {
  CASE_NUM=$((CASE_NUM + 1))
  printf 'PASS: [%d] %s\n' "$CASE_NUM" "$1"
}

# fail <label> <expected> <actual>
fail() {
  CASE_NUM=$((CASE_NUM + 1))
  printf 'FAIL: [%d] %s — expected %q got %q\n' \
    "$CASE_NUM" "$1" "$2" "$3" >&2
  FAILED=$((FAILED + 1))
}

# skip_suite <reason> — print SKIP marker and exit 0 (missing toolchain etc.).
skip_suite() {
  printf 'SKIP: %s\n' "$1" >&2
  exit 0
}

# skip_case <reason> — skip one case without exiting.
skip_case() {
  printf 'SKIP: %s\n' "$1" >&2
}

# assert_eq <label> <expected> <actual>
assert_eq() {
  local label="$1" expected="$2" actual="$3"
  if [[ "$actual" == "$expected" ]]; then
    pass "$label"
  else
    fail "$label" "$expected" "$actual"
  fi
}

# assert_contains <label> <haystack> <needle>
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

# assert_not_contains <label> <haystack> <needle>
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

# assert_silent <label> <output> — output is empty / whitespace-only.
assert_silent() {
  CASE_NUM=$((CASE_NUM + 1))
  local label="$1" output="$2"
  local trimmed="${output#"${output%%[![:space:]]*}"}"
  trimmed="${trimmed%"${trimmed##*[![:space:]]}"}"
  if [[ -z "$trimmed" ]]; then
    printf 'PASS: [%d] %s\n' "$CASE_NUM" "$label"
  else
    printf 'FAIL: [%d] %s — expected empty/whitespace, got: %s\n' \
      "$CASE_NUM" "$label" "$output" >&2
    FAILED=$((FAILED + 1))
  fi
}

# assert_exit <label> <expected_code> <actual_code>
assert_exit() {
  local label="$1" expected="$2" actual="$3"
  CASE_NUM=$((CASE_NUM + 1))
  if [[ "$actual" == "$expected" ]]; then
    printf 'PASS: [%d] %s\n' "$CASE_NUM" "$label"
  else
    printf 'FAIL: [%d] %s — exit expected %s got %s\n' \
      "$CASE_NUM" "$label" "$expected" "$actual" >&2
    FAILED=$((FAILED + 1))
  fi
}

# assert_stdout_contains <label> <output> <needle> — alias of assert_contains.
assert_stdout_contains() {
  assert_contains "$@"
}

# assert_file_exists <label> <path>
assert_file_exists() {
  CASE_NUM=$((CASE_NUM + 1))
  local label="$1" path="$2"
  if [[ -f "$path" ]]; then
    printf 'PASS: [%d] %s\n' "$CASE_NUM" "$label"
  else
    printf 'FAIL: [%d] %s — expected file %s\n' \
      "$CASE_NUM" "$label" "$path" >&2
    FAILED=$((FAILED + 1))
  fi
}

# assert_file_absent <label> <path>
assert_file_absent() {
  CASE_NUM=$((CASE_NUM + 1))
  local label="$1" path="$2"
  if [[ ! -f "$path" ]]; then
    printf 'PASS: [%d] %s\n' "$CASE_NUM" "$label"
  else
    printf 'FAIL: [%d] %s — expected absent, found %s\n' \
      "$CASE_NUM" "$label" "$path" >&2
    FAILED=$((FAILED + 1))
  fi
}
