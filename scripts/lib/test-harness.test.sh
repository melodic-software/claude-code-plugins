#!/usr/bin/env bash
# Self-test for scripts/lib/test-harness.sh.
#
# The load-bearing property is the exit contract: a suite that recorded a
# failed assertion and then called test_harness::report cannot exit 0. The
# other cases pin the print format, the sourced-only guard, the last-line
# discipline the called shape depends on, EXIT-trap interaction with the
# two suites that already occupy that slot, and re-source idempotency.
set -uo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HARNESS="$SELF_DIR/test-harness.sh"
REPO_ROOT="$(cd "$SELF_DIR/../.." && pwd)"

# shellcheck source=test-harness.sh
. "$HARNESS"

run_child() {
  local body="$1"
  local out rc
  out="$(bash -c "$body" 2>&1)" && rc=0 || rc=$?
  printf '%s\n' "$out"
  return "$rc"
}

# --- sourced-only ---------------------------------------------------------

if bash "$HARNESS" >/dev/null 2>&1; then
  fail "executing the library exited 0"
else
  rc=$?
  if [[ "$rc" -eq 2 ]]; then
    ok "executing the library exits 2"
  else
    fail "executing the library exited $rc, expected 2"
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
  ok "a recorded failure plus report exits non-zero"
else
  fail "fail+report should exit non-zero with FAIL=1, got rc=$rc out='$out'"
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
  ok "an all-pass suite exits 0 with PASS=1 FAIL=0"
else
  fail "ok+report should exit 0 with PASS=1 FAIL=0, got rc=$rc out='$out'"
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
  ok "mixed pass/fail reports PASS=2 FAIL=1 and exits non-zero"
else
  fail "mixed run should be PASS=2 FAIL=1 non-zero, got rc=$rc out='$out'"
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
  ok "a pre-source cleanup trap still runs and does not let a recorded failure exit 0"
else
  fail "pre-source trap + fail should be non-zero with cleanup, got rc=$rc out='$out'"
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
  ok "a post-source cleanup trap still runs and does not defeat the exit contract"
else
  fail "post-source trap + fail should be non-zero with cleanup, got rc=$rc out='$out'"
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
  ok "a failing cleanup trap does not turn a clean suite red"
else
  fail "failing cleanup + clean suite should exit 0, got rc=$rc out='$out'"
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
  ok "a succeeding cleanup trap does not mask a recorded failure"
else
  fail "succeeding cleanup + fail should stay non-zero, got rc=$rc out='$out'"
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
    ok "the summary prints before the caller's EXIT trap"
  else
    fail "summary-before-trap order was right but rc=$rc out='$out'"
  fi
  ;;
*)
  fail "summary should precede CALLER_TRAP, got rc=$rc out='$out'"
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
  ok "a message containing printf format specifiers is printed verbatim"
else
  fail "format specifiers should print verbatim, got rc=$rc out='$out'"
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
  ok "the summary prints exactly once despite subshells, and subshell use does not disturb exit status"
else
  fail "subshells should leave one PASS=1 FAIL=0 summary and rc=0, got rc=$rc count=$summary_count out='$out'"
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
  ok "a parent-recorded failure stays non-zero when a subshell records a pass"
else
  fail "parent fail + subshell pass should be PASS=0 FAIL=1 non-zero once, got rc=$rc count=$summary_count out='$out'"
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
  ok "counters accumulate correctly across repeated calls"
else
  fail "repeated ok/fail/report should accumulate, got rc=$rc out='$out'"
fi

# --- a suite with no assertions exits 0 -----------------------------------

out="$(
  run_child "
    . \"$HARNESS\"
    test_harness::report
  "
)" && rc=0 || rc=$?
if [[ "$rc" -eq 0 && "$out" == *"PASS=0 FAIL=0"* ]]; then
  ok "a suite with no assertions at all exits 0"
else
  fail "empty suite should exit 0 with PASS=0 FAIL=0, got rc=$rc out='$out'"
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
  ok "re-sourcing preserves a previously recorded failure and exits non-zero"
else
  fail "re-source after fail should stay PASS=0 FAIL=1 non-zero, got rc=$rc out='$out'"
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
  last="$(last_code_line "$f")"
  if [[ "$last" != "test_harness::report" ]]; then
    missing+=("${f#"$REPO_ROOT"/}:$last")
  fi
done

if ((${#missing[@]} == 0)); then
  ok "every suite that sources the harness ends with test_harness::report"
else
  fail "sourcer(s) missing trailing test_harness::report: ${missing[*]}"
fi

test_harness::report
