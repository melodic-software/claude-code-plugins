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
  local desc="$1" input="$2" expected_out="$3" expected_exit="$4" pattern="${5:-}"
  local actual_out actual_exit
  actual_out=$(bash "$PARSER" "$input" "$pattern" 2>/dev/null)
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

# Configurable grammar (W2): a consumer whose branches place the (numeric
# GitHub) issue number differently passes an ERE whose LAST capture group is
# that number. The downstream `Closes #N` needs a numeric GitHub issue id, so
# the capture must resolve to digits.
run_test "username-scoped scheme via custom pattern" "alice/1234-fix" "1234" 0 '^[^/]+/([0-9]+)-'
run_test "trailing-number scheme via custom pattern" "feat/add-widget-1234" "1234" 0 '-([0-9]+)$'
run_test "custom pattern, no match -> exit 1" "main" "" 1 '^[^/]+/([0-9]+)-'
# shellcheck disable=SC2016  # the placeholder is a literal test input, not an expansion
run_test "unsubstituted user_config placeholder falls back to default" "feat/42-x" "42" 0 '${user_config.branch_issue_pattern}'

echo
echo "Results: ${PASS} passed, ${FAIL} failed"
[[ $FAIL -eq 0 ]]
