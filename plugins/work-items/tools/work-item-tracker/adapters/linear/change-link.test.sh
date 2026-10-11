#!/usr/bin/env bash
# shellcheck disable=SC2154  # FAILED/CASE_NUM initialized by the sourced helper
# change-link: offline; the mock transport must never be called.
set -uo pipefail
S="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/change-link.sh"
D="$(dirname "$S")"
source "$D/../../lib/verb-test-helpers.sh"
# shellcheck source=mock.sh
source "$D/mock.sh"

assert_help "$S"
assert_usage_error "$S"
assert_usage_error "$S" "github:o/r#1"

lin_fixture_init
trap 'rm -rf "$LIN_FIX"' EXIT

rc="$(lin_run "$S" "linear:acme/ENG#12")"
assert_eq "id path exit 0" "0" "$rc"
assert_eq "closes uses a closing magic word" "Closes ENG-12" "$(jq -r '.closes' <<<"$(lin_out)")"
assert_eq "refs uses a non-closing magic word" "Refs ENG-12" "$(jq -r '.refs' <<<"$(lin_out)")"
assert_eq "branch ref is the identifier" "ENG-12" "$(jq -r '.branch_ref' <<<"$(lin_out)")"

rc="$(lin_run "$S" --branch-ref eng-12)"
assert_eq "lower-case branch ref exit 0" "0" "$rc"
assert_eq "branch ref qualifies against the bound workspace" "linear:acme/ENG#12" "$(jq -r '.item_id' <<<"$(lin_out)")"

rc="$(lin_run "$S" --branch-ref OPS-5)"
assert_eq "undeclared team → exit 2" "2" "$rc"
assert_contains "the refusal names config.linear.scopes" "$(lin_err)" "config.linear.scopes"

rc="$(lin_run "$S" --branch-ref 12)"
assert_eq "a bare number is not an identifier → exit 2" "2" "$rc"

assert_eq "no request was made" "" "$(lin_requests)"
[[ $FAILED -eq 0 ]] || exit 1
