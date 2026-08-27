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
