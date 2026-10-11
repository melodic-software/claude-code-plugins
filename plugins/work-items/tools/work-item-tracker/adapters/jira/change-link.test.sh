#!/usr/bin/env bash
# shellcheck disable=SC2154  # FAILED/CASE_NUM initialized by the sourced helper
# change-link: offline; the mock curl must never be called.
set -uo pipefail
S="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/change-link.sh"
source "$(dirname "$S")/../../lib/verb-test-helpers.sh"
# shellcheck source=mock.sh
source "$(dirname "$S")/mock.sh"

assert_help "$S"
assert_usage_error "$S"
assert_usage_error "$S" "github:o/r#1"

jira_fixture_init
trap 'rm -rf "$JIRA_FIX"' EXIT
jira_write_binding '["SW2"]'

jira_run "$S" "jira:test.atlassian.net/SW2#12345"
assert_eq "id path exit 0" "0" "$RC"
assert_eq "merge closes nothing" "null" "$(jq -r '.closes' <<<"$OUT")"
assert_eq "refs is the issue key" "Refs: SW2-12345" "$(jq -r '.refs' <<<"$OUT")"
assert_eq "branch ref is the issue key" "SW2-12345" "$(jq -r '.branch_ref' <<<"$OUT")"

jira_run "$S" --branch-ref SW2-12345
assert_eq "branch ref exit 0" "0" "$RC"
assert_eq "branch ref qualifies against the bound site" "jira:test.atlassian.net/SW2#12345" "$(jq -r '.item_id' <<<"$OUT")"

jira_run "$S" --branch-ref OPS-1
assert_eq "undeclared project → exit 2" "2" "$RC"
assert_contains "the refusal names project_keys" "$ERR" "project_keys"

jira_run "$S" --branch-ref sw2-1
assert_eq "lower-case key → exit 2" "2" "$RC"

assert_eq "no request was made" "absent" "$([[ -e "$JIRA_FIX/.counter" ]] && echo present || echo absent)"
[[ $FAILED -eq 0 ]] || exit 1
