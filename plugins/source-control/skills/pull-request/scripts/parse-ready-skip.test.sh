#!/usr/bin/env bash
# Tests for parse-ready-skip.sh. Expected outputs follow the `--skip` contract in
# reference/ready-for-review.md: the step names are pre_ready's five, a reason is
# required, and an unattended run is refused, so nothing is skipped by mistake.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$SCRIPT_DIR/parse-ready-skip.sh"

# shellcheck source=../../../scripts/test-helpers.sh
source "$SCRIPT_DIR/../../../scripts/test-helpers.sh"

out=$(bash "$SCRIPT" --skip code-review --reason "model is rate-limited" 2>/dev/null)
assert_exit "one step and a reason parse" 0 "$?"
assert_eq "one step prints the reason and the step" $'reason\tmodel is rate-limited\nskip\tcode-review' "$out"

out=$(bash "$SCRIPT" --reason "usage exhausted" --skip verify,security-review,base-merge 2>/dev/null)
assert_eq "several steps print in run order, whatever order they were given" \
  $'reason\tusage exhausted\nskip\tbase-merge\nskip\tsecurity-review\nskip\tverify' "$out"

out=$(bash "$SCRIPT" --skip plan-evidence --reason $'stuck\treview\nbot' 2>/dev/null)
assert_eq "control characters in the reason become spaces" $'reason\tstuck review bot\nskip\tplan-evidence' "$out"

out=$(bash "$SCRIPT" 2>/dev/null)
assert_exit "no flag is no override" 0 "$?"
assert_silent "no flag prints nothing" "$out"

out=$(bash "$SCRIPT" --unattended 2>/dev/null)
assert_exit "an unattended run with no skip is no override" 0 "$?"
assert_silent "an unattended run with no skip prints nothing" "$out"

# Every usage error exits 2 and prints nothing on stdout, so no step is skipped.
check_usage() {
  local label="$1" out code
  shift
  out=$(bash "$SCRIPT" "$@" 2>/dev/null)
  code=$?
  assert_exit "$label is a usage error" 2 "$code"
  assert_silent "$label skips nothing" "$out"
}

check_usage "an unknown step" --skip lint --reason x
check_usage "an unknown step beside a known one" --skip code-review,lint --reason x
check_usage "a step name that differs only in case" --skip Code-Review --reason x
check_usage "the flip, a fixed floor" --skip flip --reason x
check_usage "the hold check, a fixed floor" --skip hold-check --reason x
check_usage "the push, a fixed floor" --skip push --reason x
check_usage "a step listed twice" --skip verify,verify --reason x
check_usage "an empty item in the list" --skip code-review, --reason x
check_usage "an empty list" --skip "" --reason x
check_usage "a space after a comma" --skip "code-review, verify" --reason x
check_usage "--skip with no reason" --skip code-review
check_usage "an empty reason" --skip code-review --reason ""
check_usage "a whitespace-only reason" --skip code-review --reason $'  \t'
check_usage "a reason with no skip" --reason x
check_usage "--skip with no value" --skip
check_usage "--reason with no value" --skip code-review --reason
check_usage "--skip given twice" --skip code-review --skip verify --reason x
check_usage "--reason given twice" --skip code-review --reason x --reason y
check_usage "an unknown flag" --skip code-review --reason x --force
check_usage "a positional argument" 123 --skip code-review --reason x

# A run with no person present never skips, even with a valid skip.
out=$(bash "$SCRIPT" --unattended --skip code-review --reason "model is rate-limited" 2>/dev/null)
assert_exit "--skip under --unattended is refused" 3 "$?"
assert_silent "--skip under --unattended skips nothing" "$out"
out=$(bash "$SCRIPT" --skip code-review --reason x --unattended 2>/dev/null)
assert_exit "--unattended after --skip is refused too" 3 "$?"
err=$(bash "$SCRIPT" --unattended --skip code-review --reason x 2>&1 >/dev/null)
assert_contains "the refusal says why" "$err" "unattended"

[[ $FAILED -eq 0 ]] || exit 1
