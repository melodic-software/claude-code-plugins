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

HEAD_C=$(printf 'c%.0s' $(seq 40))
printf 'garbage\n' >"$READY_VERIFY_DIR/$HEAD_C"
bash "$SCRIPT" check --head "$HEAD_C" >/dev/null 2>&1
assert_exit "an unknown recorded value refuses the flip" 2 "$?"

bash "$SCRIPT" check --head "$HEAD_B" --result pass >/dev/null 2>&1
assert_exit "check with --result is a usage error" 1 "$?"

bash "$SCRIPT" record --head "$HEAD_A" --result maybe >/dev/null 2>&1
assert_exit "an unknown result is a usage error" 1 "$?"
bash "$SCRIPT" check --head abc123 >/dev/null 2>&1
assert_exit "a short sha is a usage error" 1 "$?"
bash "$SCRIPT" bogus >/dev/null 2>&1
assert_exit "an unknown subcommand is a usage error" 1 "$?"

# Without READY_VERIFY_DIR, a record made from the main checkout covers a check run from a linked
# worktree of the same repository, and the reverse.
unset READY_VERIFY_DIR
REPO="$TEST_TMPDIR/main" WT="$TEST_TMPDIR/host-run-1"
git init -q "$REPO" && git -C "$REPO" -c user.name=t -c user.email=t@t commit -q --allow-empty -m init
git -C "$REPO" worktree add -q -b feat "$WT"
HEAD_W=$(git -C "$WT" rev-parse HEAD)
(cd "$REPO" && bash "$SCRIPT" record --head "$HEAD_W" --result pass)
(cd "$WT" && bash "$SCRIPT" check --head "$HEAD_W")
assert_exit "a pass recorded from the main checkout covers a check from a linked worktree" 0 "$?"
(cd "$WT" && bash "$SCRIPT" record --head "$HEAD_W" --result fail)
(cd "$REPO" && bash "$SCRIPT" check --head "$HEAD_W" >/dev/null 2>&1)
assert_exit "a failure recorded from a linked worktree reaches a check from the main checkout" 3 "$?"

[[ $FAILED -eq 0 ]] || exit 1
