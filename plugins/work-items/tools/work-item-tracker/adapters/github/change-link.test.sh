#!/usr/bin/env bash
# shellcheck disable=SC2154  # FAILED/CASE_NUM initialized by the sourced helper
# change-link: offline, so no gh mock is needed.
set -uo pipefail
S="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/change-link.sh"
source "$(dirname "$S")/../../lib/verb-test-helpers.sh"

assert_help "$S"
assert_usage_error "$S"
assert_usage_error "$S" --nope
assert_usage_error "$S" "#12"
assert_usage_error "$S" "jira:s/SW2#1"
assert_usage_error "$S" --branch-ref 12
bash "$S" --branch-ref SW2-12 --repo acme/webapp >/dev/null 2>&1
assert_eq "a ref that is not an issue number names no item → exit 5" "5" "$?"

out="$(bash "$S" "github:acme/webapp#42" --repo acme/webapp)"
assert_eq "closes, same repo" "Closes #42" "$(jq -r '.closes' <<<"$out")"
assert_eq "refs, same repo" "Refs: #42" "$(jq -r '.refs' <<<"$out")"
assert_eq "branch ref is the number" "42" "$(jq -r '.branch_ref' <<<"$out")"
assert_eq "schema_version" "1.0" "$(jq -r '.schema_version' <<<"$out")"

out="$(bash "$S" "github:acme/webapp#42" --repo acme/other)"
assert_eq "closes, other repo" "Closes acme/webapp#42" "$(jq -r '.closes' <<<"$out")"

out="$(bash "$S" --branch-ref 42 --repo acme/webapp)"
assert_eq "branch ref qualifies in --repo" "github:acme/webapp#42" "$(jq -r '.item_id' <<<"$out")"
assert_eq "branch ref closes short" "Closes #42" "$(jq -r '.closes' <<<"$out")"
[[ $FAILED -eq 0 ]] || exit 1
