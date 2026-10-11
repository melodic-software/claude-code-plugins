#!/usr/bin/env bash
# shellcheck disable=SC2154  # FAILED/CASE_NUM initialized by the sourced helper
set -uo pipefail
S="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/change-link.sh"
source "$(dirname "$S")/../../lib/verb-test-helpers.sh"

assert_help "$S"
assert_usage_error "$S"
assert_usage_error "$S" "github:o/r#1"
assert_usage_error "$S" --branch-ref abc

out="$(bash "$S" "local-markdown:local/markdown#7")"
assert_eq "merge closes nothing" "null" "$(jq -r '.closes' <<<"$out")"
assert_eq "refs names the qualified id" "Refs: local-markdown:local/markdown#7" "$(jq -r '.refs' <<<"$out")"
assert_eq "branch ref is the number" "7" "$(jq -r '.branch_ref' <<<"$out")"

out="$(bash "$S" --branch-ref 7)"
assert_eq "branch ref qualifies in the default namespace" "local-markdown:local/markdown#7" "$(jq -r '.item_id' <<<"$out")"
out="$(bash "$S" --branch-ref 7 --repo team/store)"
assert_eq "branch ref qualifies in --repo" "local-markdown:team/store#7" "$(jq -r '.item_id' <<<"$out")"
[[ $FAILED -eq 0 ]] || exit 1
