#!/usr/bin/env bash
# shellcheck disable=SC2154  # FAILED/CASE_NUM initialized by the sourced helper
set -uo pipefail
S="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/get-item.sh"
source "$(dirname "$S")/../../lib/verb-test-helpers.sh"

assert_help "$S"
assert_usage_error "$S" --nope
# Foreign-provider ID is well-formed by the shared grammar but must be rejected by
# the local-markdown adapter (offline: fails before any storage access).
assert_usage_error "$S" "github:o/r#1"
[[ $FAILED -eq 0 ]] || exit 1
