#!/usr/bin/env bash
# Tests for parse-branch-issue.sh.
# Each case: PASS prints, FAIL prints. Non-zero exit on any FAIL.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PARSER="${SCRIPT_DIR}/parse-branch-issue.sh"

if [[ ! -x "$PARSER" ]]; then
  echo "FAIL: parser missing or not executable: $PARSER" >&2
  exit 1
fi

PASS=0
FAIL=0

run_test() {
  local desc="$1" input="$2" expected_out="$3" expected_exit="$4"
  local actual_out actual_exit
  actual_out=$(bash "$PARSER" "$input" 2>/dev/null)
  actual_exit=$?
  if [[ "$actual_out" == "$expected_out" && "$actual_exit" -eq "$expected_exit" ]]; then
    echo "PASS: $desc"
    PASS=$((PASS + 1))
  else
    echo "FAIL: $desc"
    echo "       input='$input'"
    echo "       got     out='$actual_out' exit=$actual_exit"
    echo "       wanted  out='$expected_out' exit=$expected_exit"
    FAIL=$((FAIL + 1))
  fi
}

run_test "feat/42-new-rule emits 42" "feat/42-new-rule" "42" 0
run_test "fix/123-analyzer-fp emits 123" "fix/123-analyzer-fp" "123" 0
run_test "chore/789-rename-skill emits 789" "chore/789-rename-skill" "789" 0
run_test "chore/routine-issue-555-tidy emits 555" "chore/routine-issue-555-tidy" "555" 0
run_test "feat/just-a-feature no number" "feat/just-a-feature" "" 1
run_test "worktree-foo-bar wrong prefix" "worktree-foo-bar" "" 1
run_test "cursor/abc-xyz cloud-agent no number" "cursor/abc-xyz" "" 1

echo
echo "Results: ${PASS} passed, ${FAIL} failed"
[[ $FAIL -eq 0 ]]
