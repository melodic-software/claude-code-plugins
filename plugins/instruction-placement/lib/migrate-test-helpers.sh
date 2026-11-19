# shellcheck shell=bash

CASE_NUM=0
FAILED=0

pass() {
  CASE_NUM=$((CASE_NUM + 1))
  printf 'PASS: %s\n' "$1"
}

fail() {
  CASE_NUM=$((CASE_NUM + 1))
  FAILED=$((FAILED + 1))
  printf 'FAIL: %s\n' "$1"
  printf '      %s\n' "$2"
}

assert_eq() {
  if [[ "$2" == "$3" ]]; then pass "$1"; else fail "$1" "expected [$2], got [$3]"; fi
}

assert_contains() {
  case "$2" in
    *"$3"*) pass "$1" ;;
    *) fail "$1" "expected to contain: $3" ;;
  esac
}

assert_not_contains() {
  case "$2" in
    *"$3"*) fail "$1" "expected NOT to contain: $3" ;;
    *) pass "$1" ;;
  esac
}

UNKNOWN_COMMANDS="$(mktemp)"
# shellcheck disable=SC2329 # bash invokes this by name when a command is not found
command_not_found_handle() {
  printf '%s\n' "$1" >>"$UNKNOWN_COMMANDS"
  printf 'FAIL: unknown command in the suite: %s\n' "$1"
  printf '      a helper is missing or misspelled; the check it belonged to did not run\n'
  return 127
}
