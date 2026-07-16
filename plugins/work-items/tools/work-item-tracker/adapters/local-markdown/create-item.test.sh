#!/usr/bin/env bash
# shellcheck disable=SC2154  # FAILED/CASE_NUM initialized by the sourced helper
set -uo pipefail
S="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/create-item.sh"
source "$(dirname "$S")/../../lib/verb-test-helpers.sh"

assert_help "$S"
assert_usage_error "$S" --nope
# Foreign-provider edge id is well-formed by the shared grammar but rejected here
# (offline: fails before any storage access).
assert_usage_error "$S" --title x --parent "github:o/r#1"
assert_usage_error "$S" --title x --type # --type needs a value
[[ $FAILED -eq 0 ]] || exit 1
