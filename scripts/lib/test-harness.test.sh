#!/usr/bin/env bash
# Self-test for scripts/lib/test-harness.sh.
#
# The load-bearing property is the exit contract: a suite that recorded a
# failed assertion and then called test_harness::report cannot exit 0. The
# other cases pin the print format, the sourced-only guard, and the
# last-line discipline the called shape depends on.
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
