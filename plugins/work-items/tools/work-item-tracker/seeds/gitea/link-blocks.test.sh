#!/usr/bin/env bash
# shellcheck disable=SC2154  # FAILED/CASE_NUM initialized by the sourced helper
set -uo pipefail
S="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/link-blocks.sh"
D="$(dirname "$S")"
source "$D/../../lib/verb-test-helpers.sh"
# shellcheck source=mock.sh
source "$D/mock.sh"

assert_help "$S"
assert_usage_error "$S" --nope
assert_usage_error "$S"
assert_usage_error "$S" "gitea:acme/webapp#12"
assert_usage_error "$S" "gitea:acme/webapp#12" --blocked-by
assert_usage_error "$S" "not-an-id" --blocked-by "gitea:acme/webapp#4"
assert_usage_error "$S" "gitea:acme/webapp#12" --blocked-by "not-an-id"
assert_usage_error "$S" "github:o/r#1" --blocked-by "gitea:acme/webapp#4"
assert_usage_error "$S" "gitea:acme/webapp#12" --blocked-by "gitea:acme/webapp#12"

gitea_fixture_init
trap 'rm -rf "$GITEA_FIX"' EXIT

rc="$(gitea_run "$S" "gitea:other/repo#1" --blocked-by "gitea:acme/webapp#4")"
assert_eq "out-of-scope target → exit 2" "2" "$rc"
assert_eq "nothing was requested" "" "$(gitea_requests)"
rc="$(gitea_run "$S" "gitea:acme/webapp#12" --blocked-by "gitea:other/repo#4")"
assert_eq "out-of-scope blocker → exit 2" "2" "$rc"
assert_contains "the refusal names the blocker repo" "$(gitea_err)" "other/repo"
assert_eq "still nothing requested" "" "$(gitea_requests)"

gitea_reset_routes
gitea_seed "/dependencies" 201 "$(gitea_issue_json 4 open 'the blocker')"
rc="$(gitea_run "$S" "gitea:acme/webapp#12" --blocked-by "gitea:acme/webapp#4")"
assert_eq "link → exit 0" "0" "$rc"
assert_eq "schema_version" "1.0" "$(jq -r '.schema_version' <<<"$(gitea_out)")"
assert_eq "id is the blocked item" "gitea:acme/webapp#12" "$(jq -r '.id' <<<"$(gitea_out)")"
assert_eq "blocked_by is the blocker" "gitea:acme/webapp#4" "$(jq -r '.blocked_by' <<<"$(gitea_out)")"
assert_eq "linked" "true" "$(jq -r '.linked' <<<"$(gitea_out)")"
assert_contains "the blocked item is the URL subject" "$(gitea_requests)" \
  "POST https://git.example.invalid/api/v1/repos/acme/webapp/issues/12/dependencies"

gitea_write_binding '{"scopes":["acme/webapp","acme/api"]}'
gitea_reset_routes
gitea_seed "/dependencies" 201 "$(gitea_issue_json 7 open 'cross-repo blocker')"
rc="$(gitea_run "$S" "gitea:acme/webapp#12" --blocked-by "gitea:acme/api#7")"
assert_eq "cross-repo link → exit 0" "0" "$rc"
assert_eq "blocked_by names the other repo" "gitea:acme/api#7" "$(jq -r '.blocked_by' <<<"$(gitea_out)")"

gitea_reset_routes
gitea_seed "/dependencies" 400 '{"message":"CrossRepositoryDependencies not enabled"}'
rc="$(gitea_run "$S" "gitea:acme/webapp#12" --blocked-by "gitea:acme/api#7")"
assert_eq "cross-repo disabled → exit 7" "7" "$rc"
assert_contains "the instance setting is named" "$(gitea_err)" "ALLOW_CROSS_REPOSITORY_DEPENDENCIES"
gitea_write_binding

gitea_reset_routes
gitea_seed "/dependencies" 404 '{"message":"the issue does not exist"}'
rc="$(gitea_run "$S" "gitea:acme/webapp#12" --blocked-by "gitea:acme/webapp#4")"
assert_eq "missing issue → exit 5" "5" "$rc"

gitea_reset_routes
gitea_seed "/dependencies" 423 '{"message":"repo is archived"}'
rc="$(gitea_run "$S" "gitea:acme/webapp#12" --blocked-by "gitea:acme/webapp#4")"
assert_eq "archived repo → exit 7" "7" "$rc"

[[ $FAILED -eq 0 ]] || exit 1
