# shellcheck shell=bash

[[ -n "${_WIT_TESTS_LIB_LOADED:-}" ]] && return 0
readonly _WIT_TESTS_LIB_LOADED=1

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
  printf 'FAIL: [%d] %s — expected %q got %q\n' \
    "$CASE_NUM" "$1" "$2" "$3" >&2
  FAILED=$((FAILED + 1))
}

skip_suite() {
  printf 'SKIP: %s\n' "$1" >&2
  exit 0
}

assert_eq() {
  local label="$1" expected="$2" actual="$3"
  if [[ "$actual" == "$expected" ]]; then
    pass "$label"
  else
    fail "$label" "$expected" "$actual"
  fi
}

assert_succeeds() {
  local label="$1" expected="$2" actual="$3"
  shift 3
  if "$@" >/dev/null; then
    pass "$label"
  else
    fail "$label" "$expected" "$actual"
  fi
}

assert_fails() {
  local label="$1" expected="$2" actual="$3"
  shift 3
  if "$@" >/dev/null; then
    fail "$label" "$expected" "$actual"
  else
    pass "$label"
  fi
}

assert_contains() {
  local label="$1" haystack="$2" needle="$3"
  if [[ "$haystack" == *"$needle"* ]]; then
    pass "$label"
  else
    CASE_NUM=$((CASE_NUM + 1))
    printf 'FAIL: [%d] %s — expected %q in: %s\n' \
      "$CASE_NUM" "$label" "$needle" "$haystack" >&2
    FAILED=$((FAILED + 1))
  fi
}

assert_not_contains() {
  local label="$1" haystack="$2" needle="$3"
  if [[ "$haystack" != *"$needle"* ]]; then
    pass "$label"
  else
    CASE_NUM=$((CASE_NUM + 1))
    printf 'FAIL: [%d] %s — forbidden %q present in: %s\n' \
      "$CASE_NUM" "$label" "$needle" "$haystack" >&2
    FAILED=$((FAILED + 1))
  fi
}

write_blocking_network_shim() {
  local dir="$1"
  # shellcheck disable=SC2016  # shim body is literal by design: $(basename) evaluates at shim runtime, not here
  printf '#!/usr/bin/env bash\necho "blocked: $(basename "$0")" >&2\nexit 1\n' >"$dir/gh"
  cp "$dir/gh" "$dir/curl"
  chmod +x "$dir/gh" "$dir/curl"
}
