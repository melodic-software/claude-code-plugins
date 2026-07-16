#!/usr/bin/env bash
# shellcheck disable=SC2154  # FAILED/CASE_NUM initialized by the sourced helper
set -uo pipefail
S="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/capabilities.sh"
source "$(dirname "$S")/../../lib/verb-test-helpers.sh"

assert_help "$S"
assert_usage_error "$S" unexpected-arg
# The manifest declares reclaim unsupported (offline degradation demo) — assert it
# stays false so the seam's exit-6 path keeps a live subject.
reclaim_supported="$(jq -r '.verbs.reclaim' "$(dirname "$S")/capabilities.json")"
assert_eq "reclaim declared unsupported" "false" "$reclaim_supported"
[[ $FAILED -eq 0 ]] || exit 1
