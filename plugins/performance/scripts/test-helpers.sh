# shellcheck shell=bash
# Assertion primitives and the capture runner shared by this plugin's *.test.sh
# suites. Sourced, never executed; it is not a *.test.sh, so the suite glob
# never picks it up as a suite of its own.
#
# This is NOT harness-lib.sh. That file is the production library every harness
# sources at run time; these are test-only helpers and must stay out of it.
#
# PASS lines go to stdout and FAIL lines to stderr, and every suite ends with
#   [[ "${FAILED:-0}" -eq 0 ]] || exit 1
# so a failed assertion fails the suite rather than only printing.
#
# Duplicated per plugin by design, not drift; see
# docs/conventions/shell-test-helpers/README.md at the repo root.

FAILED=0
CASE_NUM=0

# pass <label>
pass() {
  CASE_NUM=$((CASE_NUM + 1))
  printf 'PASS: [%d] %s\n' "$CASE_NUM" "$1"
}

# fail <label> <expected> <actual>
fail() {
  CASE_NUM=$((CASE_NUM + 1))
  printf 'FAIL: [%d] %s - expected %q got %q\n' "$CASE_NUM" "$1" "$2" "$3" >&2
  FAILED=$((FAILED + 1))
}

# assert_eq <label> <expected> <actual>
assert_eq() { if [[ "$3" == "$2" ]]; then pass "$1"; else fail "$1" "$2" "$3"; fi; }

# assert_contains <label> <needle> <haystack>
assert_contains() {
  if [[ "$3" == *"$2"* ]]; then pass "$1"; else fail "$1" "*$2*" "$3"; fi
}

# assert_not_contains <label> <needle> <haystack>
assert_not_contains() {
  if [[ "$3" != *"$2"* ]]; then pass "$1"; else fail "$1" "no *$2*" "$3"; fi
}

RUN_OUT=""
RUN_RC=0

# capture <command> [args...]
#
# Run a command with stderr folded into stdout, leaving what it said in RUN_OUT
# and how it exited in RUN_RC. The command substitution is also what makes it
# safe to call a harness-lib function through this: an `exit` inside one
# terminates only the substitution's subshell, so the suite survives to assert
# on the refusal.
# shellcheck disable=SC2034  # these are the function's OUTPUT, read by every sourcing suite
capture() {
  RUN_OUT="$("$@" 2>&1)"
  RUN_RC=$?
}
