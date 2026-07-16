#!/usr/bin/env bash
# shellcheck disable=SC2154  # FAILED/CASE_NUM initialized by the sourced helper
set -uo pipefail
S="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/renew-lease.sh"
source "$(dirname "$S")/../../lib/verb-test-helpers.sh"

assert_help "$S"
# id present, --lease-comment-id missing → usage error before any network call.
assert_usage_error "$S" "github:o/r#1"
[[ $FAILED -eq 0 ]] || exit 1
