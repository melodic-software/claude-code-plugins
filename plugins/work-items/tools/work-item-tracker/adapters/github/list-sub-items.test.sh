#!/usr/bin/env bash
# shellcheck disable=SC2154  # FAILED/CASE_NUM initialized by the sourced helper
# Offline contract stub — the GitHub subIssues + intersect path needs live gh, so
# its behavior is exercised by the on-demand e2e-probe; here we assert only the
# skill-script contract (--help) and the pre-I/O usage-error paths.
set -uo pipefail
S="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/list-sub-items.sh"
source "$(dirname "$S")/../../lib/verb-test-helpers.sh"

assert_help "$S"
assert_usage_error "$S"                                    # no parent id
assert_usage_error "$S" "github:o/r#1" --state bogus       # bad state
assert_usage_error "$S" "not-an-id"                        # malformed id
assert_usage_error "$S" "local-markdown:o/r#1"             # foreign provider
[[ $FAILED -eq 0 ]] || exit 1
