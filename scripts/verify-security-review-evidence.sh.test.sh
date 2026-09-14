#!/usr/bin/env bash
# Self-tests for verify-security-review-evidence.sh.
#
# These EXECUTE the guard rather than re-implement its shapes: every input is
# an environment variable, and the one API read lives in a function the tests
# substitute. A harness that copied the guard's regexes into itself and
# asserted on the copies would agree with the guard whatever the guard did.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GUARD_SCRIPT="$SCRIPT_DIR/verify-security-review-evidence.sh"

# shellcheck source=lib/test-harness.sh
. "$SCRIPT_DIR/lib/test-harness.sh"

# shellcheck disable=SC2016  # literal source for the child shell; expanding $1
# here would substitute this suite's own args.
CHILD_PROGRAM='
  source "$1"
  live_head_sha() { printf "%s\n" "${LIVE_HEAD_SHA_STUB:-}"; }
  main
'

# run_guard <expected-exit> <name> [VAR=value ...]
run_guard() {
  local expected="$1" name="$2"
  shift 2
  test_harness::run_guard "$expected" "$name" "$GUARD_SCRIPT" "$CHILD_PROGRAM" \
    LIVE_HEAD_SHA_STUB="${LIVE_HEAD_SHA_STUB:-}" "$@"
}

# The in-scope world every case below starts from. Cases that need a different
# value for one of these spell their whole environment out instead of leaning
# on `env`'s last-assignment-wins.
IN_SCOPE=(
  GITHUB_EVENT_NAME=pull_request
  GITHUB_ACTOR=kyle-sexton
  LANE_RESULT=success
  LANE_RELEVANT=true
)

IN_SCOPE_RAN=(
  "${IN_SCOPE[@]}"
  LANE_REVIEW_RAN=true
  LANE_REVIEW_FAILED=false
)

# --- the shape the guard exists to approve -----------------------------------

run_guard 0 "an in-scope run that declares a review ran passes" "${IN_SCOPE_RAN[@]}"
assert_output_contains "the pass says what it read" "the lane declares a review ran"

# --- the shape the guard exists to catch -------------------------------------

run_guard 1 "an in-scope validation skip fails closed" \
  "${IN_SCOPE[@]}" \
  LANE_REVIEW_RAN=false \
  LANE_REVIEW_FAILED=false
assert_output_contains "the failure names the skip and its remedy" "workflow-validation skip"

# --- the shapes that are not this guard's ruling to make ---------------------

run_guard 0 "an external failure defers to the lane's deliberate green" \
  "${IN_SCOPE[@]}" \
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
  "${IN_SCOPE[@]}" \
  LANE_REVIEW_RAN="" \
  GITHUB_REPOSITORY=melodic-software/claude-code-plugins \
  PR_NUMBER=1 \
  EVENT_HEAD_SHA=0000000000000000000000000000000000000000
assert_output_contains "the supersede pass names the move" "the head has moved"

LIVE_HEAD_SHA_STUB=0000000000000000000000000000000000000000 \
  run_guard 1 "an absent verdict at an unmoved head fails closed" \
  "${IN_SCOPE[@]}" \
  LANE_REVIEW_RAN="" \
  GITHUB_REPOSITORY=melodic-software/claude-code-plugins \
  PR_NUMBER=1 \
  EVENT_HEAD_SHA=0000000000000000000000000000000000000000
assert_output_contains "the failure names the stale pin as the likely cause" "predates the declared-output contract"

LIVE_HEAD_SHA_STUB="" \
  run_guard 1 "an unreadable live head fails closed rather than assuming a supersede" \
  "${IN_SCOPE[@]}" \
  LANE_REVIEW_RAN="" \
  GITHUB_REPOSITORY=melodic-software/claude-code-plugins \
  PR_NUMBER=1 \
  EVENT_HEAD_SHA=0000000000000000000000000000000000000000

run_guard 1 "an absent verdict with nothing to check the head against fails closed" \
  "${IN_SCOPE[@]}" \
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
  bad "the guard reads declared outputs, never the lane's log" \
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
  bad "scope comes from the lane's relevant output, not a second matcher" \
    "found a local scope implementation; the lane already decided this with git check-ignore"
else
  pass "scope comes from the lane's relevant output, not a second matcher"
fi

test_harness::report
