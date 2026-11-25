# shellcheck shell=bash

[[ -n "${_CLEAN_TEST_HELPERS_LOADED:-}" ]] && return 0
readonly _CLEAN_TEST_HELPERS_LOADED=1

unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_PREFIX GIT_OBJECT_DIRECTORY GIT_CONFIG
export GIT_CONFIG_GLOBAL="${GIT_CONFIG_GLOBAL:-/dev/null}" GIT_CONFIG_NOSYSTEM=1

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

_fail_with() {
  CASE_NUM=$((CASE_NUM + 1))
  printf 'FAIL: [%d] %s — %s\n' "$CASE_NUM" "$1" "$2" >&2
  FAILED=$((FAILED + 1))
}

skip_case() {
  printf 'SKIP: %s\n' "$1" >&2
}

assert_exit() {
  if [[ "$3" == "$2" ]]; then
    pass "$1"
  else
    _fail_with "$1" "exit expected $2 got $3"
  fi
}

assert_contains() {
  local detail
  if [[ "$2" == *"$3"* ]]; then
    pass "$1"
  else
    printf -v detail 'expected %q in: %s' "$3" "$2"
    _fail_with "$1" "$detail"
  fi
}

assert_not_contains() {
  local detail
  if [[ "$2" != *"$3"* ]]; then
    pass "$1"
  else
    printf -v detail 'forbidden %q present in: %s' "$3" "$2"
    _fail_with "$1" "$detail"
  fi
}

assert_file_exists() {
  if [[ -f "$2" ]]; then
    pass "$1"
  else
    _fail_with "$1" "expected file $2"
  fi
}

assert_file_absent() {
  if [[ ! -f "$2" ]]; then
    pass "$1"
  else
    _fail_with "$1" "expected absent, found $2"
  fi
}
