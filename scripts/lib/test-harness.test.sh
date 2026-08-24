#!/usr/bin/env bash
# Self-test for scripts/lib/test-harness.sh.
#
# The load-bearing property is the exit contract: a suite that recorded a
# failed assertion and then called test_harness::report cannot exit 0. The
# other cases pin the print format, the sourced-only guard, the last-line
# discipline the called shape depends on, EXIT-trap interaction with the
# two suites that already occupy that slot, and re-source idempotency.
#
# This file sources the library it tests, so it cannot trust the library's
# own counters or report return as the process exit. Parent assertions go
# through self_ok/self_fail, which keep a tally the harness functions do
# not write. After test_harness::report, a non-zero independent tally
# forces exit 1 even if report was sabotaged. A throwaway-copy mutation
# regression pins both defects: deleting report's return 1, and removing
# fail()'s increment.
set -uo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HARNESS="$SELF_DIR/test-harness.sh"
REPO_ROOT="$(cd "$SELF_DIR/../.." && pwd)"

# shellcheck source=test-harness.sh
. "$HARNESS"

# Independent tally the library cannot reach. Parent assertions must use
# these wrappers; child suites source the harness afresh and use ok/fail.
_self_pass=0
_self_fail=0

self_ok() {
  _self_pass=$((_self_pass + 1))
  ok "$@"
}

self_fail() {
  _self_fail=$((_self_fail + 1))
  fail "$@"
}

run_child() {
  local body="$1"
  local out rc
  out="$(bash -c "$body" 2>&1)" && rc=0 || rc=$?
  printf '%s\n' "$out"
  return "$rc"
}

# --- sourced-only ---------------------------------------------------------

if bash "$HARNESS" >/dev/null 2>&1; then
  self_fail "executing the library exited 0"
else
  rc=$?
  if [[ "$rc" -eq 2 ]]; then
    self_ok "executing the library exits 2"
  else
    self_fail "executing the library exited $rc, expected 2"
  fi
fi

# --- fail then report cannot exit 0 ---------------------------------------

out="$(
  run_child "
    # shellcheck source=test-harness.sh
    . \"$HARNESS\"
    fail \"recorded failure\"
    test_harness::report
  "
)" && rc=0 || rc=$?
if [[ "$rc" -ne 0 && "$out" == *"FAIL: recorded failure"* && "$out" == *"PASS=0 FAIL=1"* ]]; then
  self_ok "a recorded failure plus report exits non-zero"
else
  self_fail "fail+report should exit non-zero with FAIL=1, got rc=$rc out='$out'"
fi

# --- ok then report exits 0 -----------------------------------------------

out="$(
  run_child "
    . \"$HARNESS\"
    ok \"one pass\"
    test_harness::report
  "
)" && rc=0 || rc=$?
if [[ "$rc" -eq 0 && "$out" == *"ok: one pass"* && "$out" == *"PASS=1 FAIL=0"* ]]; then
  self_ok "an all-pass suite exits 0 with PASS=1 FAIL=0"
else
  self_fail "ok+report should exit 0 with PASS=1 FAIL=0, got rc=$rc out='$out'"
fi

# Mixed: one fail among passes still exits non-zero.
out="$(
  run_child "
    . \"$HARNESS\"
    ok \"a\"
    fail \"b\"
    ok \"c\"
    test_harness::report
  "
)" && rc=0 || rc=$?
if [[ "$rc" -ne 0 && "$out" == *"PASS=2 FAIL=1"* ]]; then
  self_ok "mixed pass/fail reports PASS=2 FAIL=1 and exits non-zero"
else
  self_fail "mixed run should be PASS=2 FAIL=1 non-zero, got rc=$rc out='$out'"
fi

# --- EXIT trap installed before the harness is sourced --------------------

out="$(
  run_child "
    trap 'echo CLEANUP_BEFORE' EXIT
    . \"$HARNESS\"
    fail \"recorded failure\"
    test_harness::report
  "
)" && rc=0 || rc=$?
if [[ "$rc" -ne 0 && "$out" == *"FAIL: recorded failure"* && "$out" == *"PASS=0 FAIL=1"* && "$out" == *"CLEANUP_BEFORE"* ]]; then
  self_ok "a pre-source cleanup trap still runs and does not let a recorded failure exit 0"
else
  self_fail "pre-source trap + fail should be non-zero with cleanup, got rc=$rc out='$out'"
fi

# --- EXIT trap installed after the harness is sourced ---------------------

out="$(
  run_child "
    . \"$HARNESS\"
    trap 'echo CLEANUP_AFTER' EXIT
    fail \"recorded failure\"
    test_harness::report
  "
)" && rc=0 || rc=$?
if [[ "$rc" -ne 0 && "$out" == *"FAIL: recorded failure"* && "$out" == *"PASS=0 FAIL=1"* && "$out" == *"CLEANUP_AFTER"* ]]; then
  self_ok "a post-source cleanup trap still runs and does not defeat the exit contract"
else
  self_fail "post-source trap + fail should be non-zero with cleanup, got rc=$rc out='$out'"
fi

# --- failing cleanup does not turn a clean suite red ----------------------

out="$(
  run_child "
    . \"$HARNESS\"
    ok \"clean\"
    trap 'echo CLEANUP_FAILS; false' EXIT
    test_harness::report
  "
)" && rc=0 || rc=$?
if [[ "$rc" -eq 0 && "$out" == *"PASS=1 FAIL=0"* && "$out" == *"CLEANUP_FAILS"* ]]; then
  self_ok "a failing cleanup trap does not turn a clean suite red"
else
  self_fail "failing cleanup + clean suite should exit 0, got rc=$rc out='$out'"
fi

# --- succeeding cleanup does not mask a recorded failure ------------------

out="$(
  run_child "
    . \"$HARNESS\"
    fail \"recorded failure\"
    trap 'echo CLEANUP_OK' EXIT
    test_harness::report
  "
)" && rc=0 || rc=$?
if [[ "$rc" -ne 0 && "$out" == *"PASS=0 FAIL=1"* && "$out" == *"CLEANUP_OK"* ]]; then
  self_ok "a succeeding cleanup trap does not mask a recorded failure"
else
  self_fail "succeeding cleanup + fail should stay non-zero, got rc=$rc out='$out'"
fi

# --- summary prints before the caller's EXIT trap -------------------------

out="$(
  run_child "
    . \"$HARNESS\"
    ok \"one\"
    trap 'echo CALLER_TRAP' EXIT
    test_harness::report
  "
)" && rc=0 || rc=$?
case "$out" in
*'PASS=1 FAIL=0'*CALLER_TRAP*)
  if [[ "$rc" -eq 0 ]]; then
    self_ok "the summary prints before the caller's EXIT trap"
  else
    self_fail "summary-before-trap order was right but rc=$rc out='$out'"
  fi
  ;;
*)
  self_fail "summary should precede CALLER_TRAP, got rc=$rc out='$out'"
  ;;
esac

# --- printf format specifiers print verbatim ------------------------------

out="$(
  run_child "
    . \"$HARNESS\"
    ok \"%s %d %q\"
    fail \"%s %d %q\"
    test_harness::report
  "
)" && rc=0 || rc=$?
if [[ "$rc" -ne 0 && "$out" == *'ok: %s %d %q'* && "$out" == *'FAIL: %s %d %q'* && "$out" == *"PASS=1 FAIL=1"* ]]; then
  self_ok "a message containing printf format specifiers is printed verbatim"
else
  self_fail "format specifiers should print verbatim, got rc=$rc out='$out'"
fi

# --- summary once despite subshells; subshells do not disturb status ------

out="$(
  run_child "
    . \"$HARNESS\"
    ok \"parent-pass\"
    ( fail \"sub-fail\"; ok \"sub-pass\" )
    test_harness::report
  "
)" && rc=0 || rc=$?
summary_count="$(printf '%s\n' "$out" | grep -c '^PASS=')"
if [[ "$rc" -eq 0 && "$summary_count" -eq 1 && "$out" == *"PASS=1 FAIL=0"* && "$out" == *'ok: parent-pass'* ]]; then
  self_ok "the summary prints exactly once despite subshells, and subshell use does not disturb exit status"
else
  self_fail "subshells should leave one PASS=1 FAIL=0 summary and rc=0, got rc=$rc count=$summary_count out='$out'"
fi

# Complementary: a parent failure stays non-zero when a subshell records a pass.
out="$(
  run_child "
    . \"$HARNESS\"
    fail \"parent-fail\"
    ( ok \"sub-pass\" )
    test_harness::report
  "
)" && rc=0 || rc=$?
summary_count="$(printf '%s\n' "$out" | grep -c '^PASS=')"
if [[ "$rc" -ne 0 && "$summary_count" -eq 1 && "$out" == *"PASS=0 FAIL=1"* ]]; then
  self_ok "a parent-recorded failure stays non-zero when a subshell records a pass"
else
  self_fail "parent fail + subshell pass should be PASS=0 FAIL=1 non-zero once, got rc=$rc count=$summary_count out='$out'"
fi

# --- counters accumulate across repeated calls ----------------------------

out="$(
  run_child "
    . \"$HARNESS\"
    ok \"a\"
    ok \"b\"
    fail \"c\"
    ok \"d\"
    test_harness::report
    ok \"e\"
    fail \"f\"
    test_harness::report
  "
)" && rc=0 || rc=$?
if [[ "$rc" -ne 0 && "$out" == *"PASS=3 FAIL=1"* && "$out" == *"PASS=4 FAIL=2"* ]]; then
  self_ok "counters accumulate correctly across repeated calls"
else
  self_fail "repeated ok/fail/report should accumulate, got rc=$rc out='$out'"
fi

# --- a suite with no assertions exits 0 -----------------------------------

out="$(
  run_child "
    . \"$HARNESS\"
    test_harness::report
  "
)" && rc=0 || rc=$?
if [[ "$rc" -eq 0 && "$out" == *"PASS=0 FAIL=0"* ]]; then
  self_ok "a suite with no assertions at all exits 0"
else
  self_fail "empty suite should exit 0 with PASS=0 FAIL=0, got rc=$rc out='$out'"
fi

# --- re-sourcing must not reset recorded failures -------------------------

out="$(
  run_child "
    . \"$HARNESS\"
    fail \"recorded failure\"
    . \"$HARNESS\"
    test_harness::report
  "
)" && rc=0 || rc=$?
if [[ "$rc" -ne 0 && "$out" == *"FAIL: recorded failure"* && "$out" == *"PASS=0 FAIL=1"* ]]; then
  self_ok "re-sourcing preserves a previously recorded failure and exits non-zero"
else
  self_fail "re-source after fail should stay PASS=0 FAIL=1 non-zero, got rc=$rc out='$out'"
fi

# --- last-line discipline -------------------------------------------------

last_code_line() {
  local f="$1"
  awk '
    { gsub(/\r$/, "") }
    /^[[:space:]]*#/ { next }
    /^[[:space:]]*$/ { next }
    { last=$0 }
    END { print last }
  ' "$f"
}

sources_harness() {
  grep -qE 'lib/test-harness\.sh|source=test-harness\.sh' "$1"
}

shopt -s nullglob
missing=()
for f in "$REPO_ROOT"/scripts/*.test.sh "$REPO_ROOT"/scripts/lib/*.test.sh; do
  sources_harness "$f" || continue
  # This self-test follows report with an independent-tally check. Every
  # other sourcer must still end on the call.
  if [[ "$f" -ef "${BASH_SOURCE[0]}" ]]; then
    continue
  fi
  last="$(last_code_line "$f")"
  if [[ "$last" != "test_harness::report" ]]; then
    missing+=("${f#"$REPO_ROOT"/}:$last")
  fi
done

if ((${#missing[@]} == 0)); then
  self_ok "every suite that sources the harness ends with test_harness::report"
else
  self_fail "sourcer(s) missing trailing test_harness::report: ${missing[*]}"
fi

# --- mutated harness cannot silence this self-test --------------------------
#
# Two mutations against a throwaway copy: delete report's `return 1`, and
# remove fail()'s increment. Both print FAIL lines and still exited 0 when
# the suite trusted the library's own counters. The independent tally is
# the only signal the library cannot reach.

run_mutated_self_test() {
  local label="$1"
  local mutate="$2"
  local scratch copied_h copied_t rc

  scratch="$(mktemp -d "${TMPDIR:-/tmp}/harness-mut.XXXXXX")"
  mkdir -p "$scratch/scripts/lib"
  copied_h="$scratch/scripts/lib/test-harness.sh"
  copied_t="$scratch/scripts/lib/test-harness.test.sh"
  cp "$HARNESS" "$copied_h"
  cp "${BASH_SOURCE[0]}" "$copied_t"
  chmod +x "$copied_t"

  case "$mutate" in
  drop-return-1)
    grep -v '^[[:space:]]*return 1$' "$HARNESS" >"$copied_h"
    ;;
  drop-fail-increment)
    # Literal increment text from fail(); $(( must not expand here.
    # shellcheck disable=SC2016
    grep -Fv '_test_harness_fail=$((_test_harness_fail + 1))' "$HARNESS" >"$copied_h"
    ;;
  *)
    rm -rf "$scratch"
    self_fail "unknown mutation: $mutate"
    return 0
    ;;
  esac

  if cmp -s "$HARNESS" "$copied_h"; then
    rm -rf "$scratch"
    self_fail "mutation did not change the harness: $label"
    return 0
  fi

  TEST_HARNESS_SKIP_MUTATION_REGRESSION=1 bash "$copied_t" >/dev/null 2>&1 && rc=0 || rc=$?
  rm -rf "$scratch"

  if [[ "$rc" -ne 0 ]]; then
    self_ok "self-test still exits non-zero after: $label"
  else
    self_fail "self-test exited 0 after mutation: $label"
  fi
}

if [[ -z "${TEST_HARNESS_SKIP_MUTATION_REGRESSION:-}" ]]; then
  run_mutated_self_test "delete return 1 from report" drop-return-1
  run_mutated_self_test "remove fail increment" drop-fail-increment
fi

# The library's own report/counters are under test. An independent tally
# is the only signal CI can trust when those are sabotaged.
test_harness::report
report_rc=$?
if ((_self_fail > 0)); then
  exit 1
fi
exit "$report_rc"
