# shellcheck shell=bash
# Self-contained assertion helpers for the repo-hygiene clean tests.
# Duplicated across plugins by design: docs/contracts/shell-test-helpers/README.md.
#
# Each test file owns its own FAILED / CASE_NUM counters and exits non-zero at
# the end: `[[ $FAILED -eq 0 ]] || exit 1`.

[[ -n "${_CLEAN_TEST_HELPERS_LOADED:-}" ]] && return 0
readonly _CLEAN_TEST_HELPERS_LOADED=1

# Strip inherited git-hook context so a fixture `git init` in these tests
# resolves to the mktemp fixture, never the real repo (a git-hook chain exports
# GIT_DIR / GIT_INDEX_FILE etc.).
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_PREFIX GIT_OBJECT_DIRECTORY GIT_CONFIG

: "${FAILED:=0}"
: "${CASE_NUM:=0}"

pass() {
  CASE_NUM=$((CASE_NUM + 1))
  printf 'PASS: [%d] %s\n' "$CASE_NUM" "$1"
}

fail() {
  CASE_NUM=$((CASE_NUM + 1))
  printf 'FAIL: [%d] %s — expected %q got %q\n' "$CASE_NUM" "$1" "$2" "$3" >&2
  FAILED=$((FAILED + 1))
}

# _fail_with <label> <detail>: record a failing case with a preformatted detail.
_fail_with() {
  CASE_NUM=$((CASE_NUM + 1))
  printf 'FAIL: [%d] %s — %s\n' "$CASE_NUM" "$1" "$2" >&2
  FAILED=$((FAILED + 1))
}

# skip_case <reason> — print SKIP marker without exiting or bumping CASE_NUM.
skip_case() {
  printf 'SKIP: %s\n' "$1" >&2
}

# assert_exit <label> <expected_code> <actual_code>
assert_exit() {
  if [[ "$3" == "$2" ]]; then
    pass "$1"
  else
    _fail_with "$1" "exit expected $2 got $3"
  fi
}

# assert_contains <label> <haystack> <needle> — substring presence.
assert_contains() {
  local detail
  if [[ "$2" == *"$3"* ]]; then
    pass "$1"
  else
    printf -v detail 'expected %q in: %s' "$3" "$2"
    _fail_with "$1" "$detail"
  fi
}

# assert_not_contains <label> <haystack> <needle> — substring absence.
assert_not_contains() {
  local detail
  if [[ "$2" != *"$3"* ]]; then
    pass "$1"
  else
    printf -v detail 'forbidden %q present in: %s' "$3" "$2"
    _fail_with "$1" "$detail"
  fi
}

# assert_file_exists <label> <path>
assert_file_exists() {
  if [[ -f "$2" ]]; then
    pass "$1"
  else
    _fail_with "$1" "expected file $2"
  fi
}

# assert_file_absent <label> <path>
assert_file_absent() {
  if [[ ! -f "$2" ]]; then
    pass "$1"
  else
    _fail_with "$1" "expected absent, found $2"
  fi
}
