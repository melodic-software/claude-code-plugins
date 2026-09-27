# shellcheck shell=bash
# Shared assertion scaffolding for scripts/*.test.sh. Sourced, never executed.
#
# One library owns the pass-recording / fail-recording / summary / exit-status
# contract. Per-suite copies of the counters, ok()/fail(), and the trailing
# summary would be free to disagree on the part that matters: a suite whose
# summary is wrong can print failures and still exit 0, and CI would treat
# that as green.
#
# This is the called shape, not an EXIT trap. Bash runs exactly one EXIT trap
# per shell; an installed summary contended with the suites that already use
# that slot for fixture cleanup (check-skill-portability.test.sh,
# check-silent-revert.test.sh). test_harness::report is each suite's last
# line; the trap slot stays the caller's. A suite that exits before the call
# skips the verdict — the harness's own suite asserts that every sourcer ends
# with the call, so a migration that drops it cannot land quietly.
#
# Beyond the counters it also owns the two shapes every repo-tooling suite that
# drives a SCRIPT rather than a function needs: test_harness::run_guard, which
# executes that script in a clean environment and records the exit-status
# comparison, and assert_output_contains, which asserts on what it printed.
# One library keeps the clean environment, which decides whether one case can
# leak into the next, in one place.
#
# Plugin *.test.sh helpers stay duplicated on purpose; see
# docs/conventions/shell-test-helpers/README.md. This file is the repo-tooling
# layer only.

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  printf 'scripts/lib/test-harness.sh is sourced-only\n' >&2
  exit 2
fi

# A second source (direct or transitive) must not zero recorded results: that
# is the same false-green this file exists to abolish. The functions stay.
if [[ -n "${TEST_HARNESS_SOURCED:-}" ]]; then
  return 0
fi
TEST_HARNESS_SOURCED=1

_test_harness_pass=0
_test_harness_fail=0

ok() {
  printf 'ok: %s\n' "$*"
  _test_harness_pass=$((_test_harness_pass + 1))
}

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  _test_harness_fail=$((_test_harness_fail + 1))
}

pass() { ok "$1"; }
# Two-argument shape: a label plus the detail that explains the failure. The
# harness owns the counter and the exit contract.
bad() { fail "$1${2:+: $2}"; }

# assert_output_contains <name> <needle>
# Asserts on LAST_OUTPUT, the combined output test_harness::run_guard captured.
assert_output_contains() {
  local name="$1" needle="$2"
  if [[ "$LAST_OUTPUT" == *"$needle"* ]]; then
    pass "$name"
  else
    bad "$name" "expected output to contain '$needle'; got: $LAST_OUTPUT"
  fi
}

# test_harness::run_guard <expected-exit> <name> <script> <child-program> [VAR=value ...]
#
# Runs <script> in a separate bash process with only the named environment, so
# one case cannot leak state into the next and so `set -e` is genuinely in
# force: a subshell would inherit the suite's suppressed state and hide the very
# failures these cases exist to catch. <child-program> is literal source for
# that process and receives <script> as "$1"; it sources the script, replaces
# whatever the case stubs out, and calls main.
#
# `$0` is deliberately NOT the script's path: a guard runs `main` on its own
# when `BASH_SOURCE[0]` equals `$0`, so sourcing it as `$0` would execute it
# before the stub could replace anything.
#
# Records the comparison through pass/bad and leaves the combined output in
# LAST_OUTPUT.
test_harness::run_guard() {
  local expected="$1" name="$2" script="$3" program="$4"
  shift 4
  local output status
  output="$(
    env -i \
      PATH="$PATH" \
      HOME="${HOME:-/tmp}" \
      "$@" \
      bash -c "$program" harness "$script" 2>&1
  )"
  status=$?
  LAST_OUTPUT="$output"
  if [[ "$status" -eq "$expected" ]]; then
    pass "$name"
    return 0
  fi
  bad "$name" "expected exit $expected, got $status; output: $output"
  return 1
}

# test_harness::report
# Prints PASS/FAIL totals and returns 1 when any fail() was recorded, else 0.
# Invoke as the suite's last line so the return is the script's exit status.
test_harness::report() {
  printf 'PASS=%d FAIL=%d\n' "$_test_harness_pass" "$_test_harness_fail"
  if ((_test_harness_fail > 0)); then
    return 1
  fi
  return 0
}
