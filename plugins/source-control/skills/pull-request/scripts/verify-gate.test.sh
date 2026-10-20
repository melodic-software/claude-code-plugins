#!/usr/bin/env bash
# Regression tests for verify-gate.sh: the ready flip needs a recorded pass (or skip) for the head.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$SCRIPT_DIR/verify-gate.sh"
TEST_TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TEST_TMPDIR"' EXIT

# shellcheck source=../../../scripts/test-helpers.sh
source "$SCRIPT_DIR/../../../scripts/test-helpers.sh"

export READY_VERIFY_DIR="$TEST_TMPDIR/state"
HEAD_A=$(printf 'a%.0s' $(seq 40))
HEAD_B=$(printf 'b%.0s' $(seq 40))

out=$(bash "$SCRIPT" check --head "$HEAD_A" 2>&1)
assert_exit "a missing result refuses the flip" 2 "$?"
assert_contains "the missing-result refusal names the head" "$out" "$HEAD_A"

bash "$SCRIPT" record --head "$HEAD_A" --result fail
assert_exit "recording a failed result succeeds" 0 "$?"
out=$(bash "$SCRIPT" check --head "$HEAD_A" 2>&1)
assert_exit "a failed result refuses the flip" 3 "$?"
assert_contains "the failure refusal says the gate failed" "$out" "failed"

bash "$SCRIPT" record --head "$HEAD_A" --result pass
out=$(bash "$SCRIPT" check --head "$HEAD_A" 2>&1)
assert_exit "a recorded pass lets the flip go on" 0 "$?"
assert_silent "a pass prints nothing" "$out"

bash "$SCRIPT" check --head "$HEAD_B" >/dev/null 2>&1
assert_exit "a pass on another head does not cover this head" 2 "$?"

bash "$SCRIPT" record --head "$HEAD_B" --result skipped
bash "$SCRIPT" check --head "$HEAD_B" >/dev/null 2>&1
assert_exit "a recorded skip for the head lets the flip go on" 0 "$?"

bash "$SCRIPT" record --head "$HEAD_A" --result fail
bash "$SCRIPT" check --head "$HEAD_A" >/dev/null 2>&1
assert_exit "a later failure replaces an earlier pass" 3 "$?"

bash "$SCRIPT" record --head "$HEAD_A" --result maybe >/dev/null 2>&1
assert_exit "an unknown result is a usage error" 1 "$?"
bash "$SCRIPT" check --head abc123 >/dev/null 2>&1
assert_exit "a short sha is a usage error" 1 "$?"
bash "$SCRIPT" bogus >/dev/null 2>&1
assert_exit "an unknown subcommand is a usage error" 1 "$?"

[[ $FAILED -eq 0 ]] || exit 1
