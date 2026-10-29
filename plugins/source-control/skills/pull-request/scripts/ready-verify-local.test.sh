#!/usr/bin/env bash
# test-scope: plugins/source-control/skills/pull-request/SKILL.md
# test-scope: plugins/source-control/skills/pull-request/reference/ready-for-review.md
# Skill-text tests for the ready action's CI test-lane skip: the verify step reads
# review-venue.sh's tests line for the head it flips, reports a skip as
# `skipped (CI covers it)`, and `ready --verify-local` runs the suites anyway.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
SKILL="$SKILL_DIR/SKILL.md"
REF="$SKILL_DIR/reference/ready-for-review.md"

# shellcheck source=../../../scripts/test-helpers.sh
source "$SCRIPT_DIR/../../../scripts/test-helpers.sh"

skill=$(cat "$SKILL")
ref=$(cat "$REF")

assert_contains "SKILL.md names the --verify-local flag" "$skill" "ready --verify-local"
assert_contains "SKILL.md names the skip line" "$skill" "skipped (CI covers it)"
assert_contains "the ready reference names the --verify-local flag" "$ref" "ready --verify-local"
assert_contains "the ready reference names the skip line" "$ref" "skipped (CI covers it)"
# shellcheck disable=SC2016 # the literal command text, not an expansion
assert_contains "the ready reference reads the tests line for the PR worktree's HEAD" "$ref" \
  'review-venue.sh" --head "$(git -C "$PR_TREE" rev-parse HEAD)"'
assert_contains "a CI-covered verify records skipped" "$ref" "the venue's \`tests\` line read \`ci\`"

[[ $FAILED -eq 0 ]] || exit 1
