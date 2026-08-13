#!/usr/bin/env bash
# Self-tests for verify-security-review-evidence.sh.
#
# These EXECUTE the guard rather than re-implement its shapes. That became
# possible when the guard stopped scraping the lane's job log and started
# reading the lane's declared outputs: every input is now an environment
# variable, and the one API read left behind lives in a function the tests
# substitute. The previous harness could only copy the guard's regexes into
# itself and assert on the copies, which is why it agreed with a guard that was
# reddening every pull request it exists to approve (#2517).
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GUARD_SCRIPT="$SCRIPT_DIR/verify-security-review-evidence.sh"

FAILED=0
pass() { printf 'PASS: %s\n' "$1"; }
fail() {
  FAILED=$((FAILED + 1))
  printf 'FAIL: %s\n  %s\n' "$1" "$2" >&2
}

# run_guard <expected-exit> <name> [VAR=value ...]
#
# Runs the guard in a separate bash process with only the named environment,
# so one case cannot leak state into the next and so `set -e` is genuinely in
# force — a subshell would inherit this harness's suppressed state and hide the
# very failures these cases exist to catch.
#
# `$0` is deliberately NOT the guard's path: the guard runs `main` on its own
# when `BASH_SOURCE[0]` equals `$0`, so sourcing it as `$0` would execute it
# before the stub could replace anything.
run_guard() {
  local expected="$1" name="$2"
  shift 2
  local output status
  # shellcheck disable=SC2016  # the bash -c body is literal source for the
  # child shell; expanding $1 here would substitute this harness's own args.
  output="$(env -i \
    PATH="$PATH" \
    HOME="${HOME:-/tmp}" \
    LIVE_HEAD_SHA_STUB="${LIVE_HEAD_SHA_STUB:-}" \
    "$@" \
    bash -c '
      source "$1"
      live_head_sha() { printf "%s\n" "${LIVE_HEAD_SHA_STUB:-}"; }
      main
    ' harness "$GUARD_SCRIPT" 2>&1)"
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

IN_SCOPE_RAN=(
  GITHUB_EVENT_NAME=pull_request
  GITHUB_ACTOR=kyle-sexton
  LANE_RESULT=success
  LANE_RELEVANT=true
  LANE_REVIEW_RAN=true
  LANE_REVIEW_FAILED=false
)

# --- the shape the guard exists to approve -----------------------------------

run_guard 0 "an in-scope run that declares a review ran passes" "${IN_SCOPE_RAN[@]}"
assert_output_contains "the pass says what it read" "the lane declares a review ran"

# --- the shape the guard exists to catch -------------------------------------

run_guard 1 "an in-scope validation skip fails closed" \
  GITHUB_EVENT_NAME=pull_request \
  GITHUB_ACTOR=kyle-sexton \
  LANE_RESULT=success \
  LANE_RELEVANT=true \
  LANE_REVIEW_RAN=false \
  LANE_REVIEW_FAILED=false
assert_output_contains "the failure names the skip and its remedy" "workflow-validation skip"

# --- the shapes that are not this guard's ruling to make ---------------------

run_guard 0 "an external failure defers to the lane's deliberate green" \
  GITHUB_EVENT_NAME=pull_request \
  GITHUB_ACTOR=kyle-sexton \
  LANE_RESULT=success \
  LANE_RELEVANT=true \
  LANE_REVIEW_RAN=false \
  LANE_REVIEW_FAILED=true \
  LANE_FAILURE_CLASS=rate-limit
assert_output_contains "deferring still says nothing was reviewed" "Nothing was reviewed at this head"

run_guard 0 "an out-of-scope pull request is waved through, not failed" \
  GITHUB_EVENT_NAME=pull_request \
  GITHUB_ACTOR=kyle-sexton \
  LANE_RESULT=success \
  LANE_RELEVANT=false \
  LANE_REVIEW_RAN="" \
  LANE_REVIEW_FAILED=""

run_guard 0 "a skipped lane job is not applicable" \
  GITHUB_EVENT_NAME=pull_request \
  GITHUB_ACTOR=kyle-sexton \
  LANE_RESULT=skipped

run_guard 0 "a failed lane job defers to the job's own red" \
  GITHUB_EVENT_NAME=pull_request \
  GITHUB_ACTOR=kyle-sexton \
  LANE_RESULT=failure

run_guard 0 "a skip-listed actor is not applicable" \
  GITHUB_EVENT_NAME=pull_request \
  GITHUB_ACTOR="dependabot[bot]" \
  LANE_RESULT=success \
  LANE_RELEVANT=true \
  LANE_REVIEW_RAN=false \
  LANE_REVIEW_FAILED=false

run_guard 0 "a non-pull_request event is not applicable" \
  GITHUB_EVENT_NAME=push \
  LANE_RESULT=success

# --- absent verdict: fail closed unless the head demonstrably moved ----------

LIVE_HEAD_SHA_STUB=1111111111111111111111111111111111111111 \
  run_guard 0 "a retired superseded run is recognised by a moved head" \
  GITHUB_EVENT_NAME=pull_request \
  GITHUB_ACTOR=kyle-sexton \
  LANE_RESULT=success \
  LANE_RELEVANT=true \
  LANE_REVIEW_RAN="" \
  GITHUB_REPOSITORY=melodic-software/claude-code-plugins \
  PR_NUMBER=1 \
  EVENT_HEAD_SHA=0000000000000000000000000000000000000000
assert_output_contains "the supersede pass names the move" "the head has moved"

LIVE_HEAD_SHA_STUB=0000000000000000000000000000000000000000 \
  run_guard 1 "an absent verdict at an unmoved head fails closed" \
  GITHUB_EVENT_NAME=pull_request \
  GITHUB_ACTOR=kyle-sexton \
  LANE_RESULT=success \
  LANE_RELEVANT=true \
  LANE_REVIEW_RAN="" \
  GITHUB_REPOSITORY=melodic-software/claude-code-plugins \
  PR_NUMBER=1 \
  EVENT_HEAD_SHA=0000000000000000000000000000000000000000
assert_output_contains "the failure names the stale pin as the likely cause" "predates the declared-output contract"

LIVE_HEAD_SHA_STUB="" \
  run_guard 1 "an unreadable live head fails closed rather than assuming a supersede" \
  GITHUB_EVENT_NAME=pull_request \
  GITHUB_ACTOR=kyle-sexton \
  LANE_RESULT=success \
  LANE_RELEVANT=true \
  LANE_REVIEW_RAN="" \
  GITHUB_REPOSITORY=melodic-software/claude-code-plugins \
  PR_NUMBER=1 \
  EVENT_HEAD_SHA=0000000000000000000000000000000000000000

run_guard 1 "an absent verdict with nothing to check the head against fails closed" \
  GITHUB_EVENT_NAME=pull_request \
  GITHUB_ACTOR=kyle-sexton \
  LANE_RESULT=success \
  LANE_RELEVANT=true \
  LANE_REVIEW_RAN=""

run_guard 1 "a guard not wired to the lane at all fails closed" \
  GITHUB_EVENT_NAME=pull_request \
  GITHUB_ACTOR=kyle-sexton \
  LANE_RESULT=""

# --- static guards on the source ---------------------------------------------

# The defect this rewrite removes. A log read is not a contract: the lane's
# `Report review outcome` step is an inline github-script whose source is echoed
# into the same log, so any grep for the phrases that name a skip also matches
# the source that mentions them (#2517).
if grep -qE 'gh run view|--log' "$GUARD_SCRIPT"; then
  fail "the guard reads declared outputs, never the lane's log" \
    "found a log read; the lane's echoed github-script source contains the skip phrases as string literals (#2517)"
else
  pass "the guard reads declared outputs, never the lane's log"
fi

# One matcher, upstream. A second local implementation of the paths matcher is
# what produced the `set -e` scope-verdict defect and disagreed with the lane's
# `git check-ignore` semantics besides.
# Comment lines are excluded on purpose — the guard's header explains the
# defect by naming it, and a check that cannot tell an explanation from an
# implementation would forbid recording why this shape is gone.
if grep -vE '^[[:space:]]*#' "$GUARD_SCRIPT" | grep -qE 'python3|fnmatch|pr_touches_security_paths'; then
  fail "scope comes from the lane's relevant output, not a second matcher" \
    "found a local scope implementation; the lane already decided this with git check-ignore"
else
  pass "scope comes from the lane's relevant output, not a second matcher"
fi

if [[ "$FAILED" -eq 0 ]]; then
  printf '\nAll checks passed.\n'
  exit 0
fi
exit 1
