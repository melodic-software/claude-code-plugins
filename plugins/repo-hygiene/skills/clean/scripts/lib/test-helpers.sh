# shellcheck shell=bash
# Self-contained assertion helpers for the repo-hygiene clean tests.
# Sourced by every sibling *.test.sh via a plugin-relative BASH_SOURCE path so
# the tests stay portable under plugin cache isolation (no reach-out to a
# repo-level shared lib). Mirrors the per-plugin test-helper precedent in this
# marketplace (guardrails, source-control).
#
# Each test file owns its own FAILED / CASE_NUM counters and exits non-zero at
# the end: `[[ $FAILED -eq 0 ]] || exit 1`.
#
# Duplicated across plugins by design, not drift — see
# docs/conventions/shell-test-helpers/README.md at the repo root.

[[ -n "${_CLEAN_TEST_HELPERS_LOADED:-}" ]] && return 0
readonly _CLEAN_TEST_HELPERS_LOADED=1

# Strip inherited git-hook context so a fixture `git init` in these tests
# resolves to the mktemp fixture, never the real repo (a git-hook chain exports
# GIT_DIR / GIT_INDEX_FILE etc.).
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_PREFIX GIT_OBJECT_DIRECTORY

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

# skip_case <reason> — print SKIP marker without exiting or bumping CASE_NUM.
skip_case() {
  printf 'SKIP: %s\n' "$1" >&2
}

# assert_exit <label> <expected_code> <actual_code>
assert_exit() {
  local label="$1" expected="$2" actual="$3"
  CASE_NUM=$((CASE_NUM + 1))
  if [[ "$actual" == "$expected" ]]; then
    printf 'PASS: [%d] %s\n' "$CASE_NUM" "$label"
  else
    printf 'FAIL: [%d] %s — exit expected %s got %s\n' "$CASE_NUM" "$label" "$expected" "$actual" >&2
    FAILED=$((FAILED + 1))
  fi
}

# assert_contains <label> <haystack> <needle> — substring presence.
assert_contains() {
  CASE_NUM=$((CASE_NUM + 1))
  local label="$1" haystack="$2" needle="$3"
  if [[ "$haystack" == *"$needle"* ]]; then
    printf 'PASS: [%d] %s\n' "$CASE_NUM" "$label"
  else
    printf 'FAIL: [%d] %s — expected %q in: %s\n' "$CASE_NUM" "$label" "$needle" "$haystack" >&2
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
    printf 'FAIL: [%d] %s — forbidden %q present in: %s\n' "$CASE_NUM" "$label" "$needle" "$haystack" >&2
    FAILED=$((FAILED + 1))
  fi
}

# assert_file_exists <label> <path>
assert_file_exists() {
  CASE_NUM=$((CASE_NUM + 1))
  local label="$1" path="$2"
  if [[ -f "$path" ]]; then
    printf 'PASS: [%d] %s\n' "$CASE_NUM" "$label"
  else
    printf 'FAIL: [%d] %s — expected file %s\n' "$CASE_NUM" "$label" "$path" >&2
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
    printf 'FAIL: [%d] %s — expected absent, found %s\n' "$CASE_NUM" "$label" "$path" >&2
    FAILED=$((FAILED + 1))
  fi
}
