#!/usr/bin/env bash
# Self-tests for verify-claude-review-skill.sh.
#
# These EXECUTE the guard. Review bodies are injected by substituting
# fetch_review_bodies, so the cases never call the GitHub API.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GUARD_SCRIPT="$SCRIPT_DIR/verify-claude-review-skill.sh"

FAILED=0
pass() { printf 'PASS: %s\n' "$1"; }
fail() {
  FAILED=$((FAILED + 1))
  printf 'FAIL: %s\n  %s\n' "$1" "$2" >&2
}

# run_guard <expected-exit> <name> <body-stub> [VAR=value ...]
run_guard() {
  local expected="$1" name="$2" body_stub="$3"
  shift 3
  local output status
  output="$(
    REVIEW_BODY_STUB="$body_stub" \
      env -i \
      PATH="$PATH" \
      HOME="${HOME:-/tmp}" \
      REVIEW_BODY_STUB="$body_stub" \
      "$@" \
      bash -c '
      source "$1"
      fetch_review_bodies() { printf "%s\n" "${REVIEW_BODY_STUB}"; }
      main
    ' harness "$GUARD_SCRIPT" 2>&1
  )"
  status=$?
  if [[ "$status" -eq "$expected" ]]; then
    pass "$name"
    LAST_OUTPUT="$output"
    return 0
  fi
  fail "$name" "expected exit $expected, got $status; output: $output"
  LAST_OUTPUT="$output"
  return 1
}

assert_output_contains() {
  local name="$1" needle="$2"
  if [[ "$LAST_OUTPUT" == *"$needle"* ]]; then
    pass "$name"
  else
    fail "$name" "expected output to contain '$needle'; got: $LAST_OUTPUT"
  fi
}

BASE=(
  GITHUB_EVENT_NAME=pull_request
  GITHUB_ACTOR=kyle-sexton
  GITHUB_REPOSITORY=melodic-software/claude-code-plugins
  PR_NUMBER=3147
  EVENT_HEAD_SHA=abc123
  LANE_RESULT=success
)

DEGRADE=$'the `review:code-review` Skill invocation errored out in this environment (returned `<error>Execute skill: review:code-review</error>` on repeated attempts with no further detail) and I fell back to a manual diff review.'

CLEAN=$'## Findings\n\n1. The helper should fail closed.\n\nReviewed via /review:code-review.'

# --- the shape the guard exists to catch -------------------------------------

run_guard 1 "silent skill fallback on a green lane fails" "$DEGRADE" "${BASE[@]}"
assert_output_contains "names the defect" "Skill-tool failure"

# --- the shape the guard exists to approve -----------------------------------

run_guard 0 "a skill-based review passes" "$CLEAN" "${BASE[@]}"
assert_output_contains "skill-based OK" "skill evidence OK"

# A code citation of one needle is not the degrade path.
run_guard 0 "quoting the error tag without a fallback is not a degrade" \
  $'The workflow should fail when the log contains `<error>Execute skill: review:code-review</error>`.' \
  "${BASE[@]}"

run_guard 0 "quoting fallback without a skill error is not a degrade" \
  $'Do not silently substitute a manual diff review.' \
  "${BASE[@]}"

# --- not-applicable paths ----------------------------------------------------

run_guard 0 "non-pull_request is not applicable" "$DEGRADE" \
  GITHUB_EVENT_NAME=push LANE_RESULT=success GITHUB_ACTOR=kyle-sexton \
  GITHUB_REPOSITORY=melodic-software/claude-code-plugins PR_NUMBER=1

run_guard 0 "skip-listed actor is not applicable" "$DEGRADE" \
  GITHUB_EVENT_NAME=pull_request GITHUB_ACTOR=dependabot[bot] \
  LANE_RESULT=success GITHUB_REPOSITORY=melodic-software/claude-code-plugins \
  PR_NUMBER=1

run_guard 0 "skipped lane is not applicable" "$DEGRADE" \
  GITHUB_EVENT_NAME=pull_request GITHUB_ACTOR=kyle-sexton \
  LANE_RESULT=skipped GITHUB_REPOSITORY=melodic-software/claude-code-plugins \
  PR_NUMBER=1

run_guard 0 "cancelled lane is not applicable" "$DEGRADE" \
  GITHUB_EVENT_NAME=pull_request GITHUB_ACTOR=kyle-sexton \
  LANE_RESULT=cancelled GITHUB_REPOSITORY=melodic-software/claude-code-plugins \
  PR_NUMBER=1

run_guard 0 "already-failed lane is not applicable" "$DEGRADE" \
  GITHUB_EVENT_NAME=pull_request GITHUB_ACTOR=kyle-sexton \
  LANE_RESULT=failure GITHUB_REPOSITORY=melodic-software/claude-code-plugins \
  PR_NUMBER=1

run_guard 1 "empty LANE_RESULT fails closed" "$CLEAN" \
  GITHUB_EVENT_NAME=pull_request GITHUB_ACTOR=kyle-sexton \
  GITHUB_REPOSITORY=melodic-software/claude-code-plugins PR_NUMBER=1

run_guard 1 "missing repo/pr fails closed on a successful lane" "$CLEAN" \
  GITHUB_EVENT_NAME=pull_request GITHUB_ACTOR=kyle-sexton \
  LANE_RESULT=success

# --- help --------------------------------------------------------------------

help_out="$(bash "$GUARD_SCRIPT" --help)"
help_status=$?
if [[ "$help_status" -eq 0 && "$help_out" == *'verify-claude-review-skill.sh'* ]]; then
  pass "--help exits 0"
else
  fail "--help exits 0" "status=$help_status output=$help_out"
fi

if [[ "$FAILED" -eq 0 ]]; then
  printf '\nAll checks passed.\n'
  exit 0
fi
printf '\n%d checks failed.\n' "$FAILED" >&2
exit 1
