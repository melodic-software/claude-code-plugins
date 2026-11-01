#!/usr/bin/env bash
# shellcheck disable=SC2154  # FAILED/CASE_NUM initialized by the sourced helper
# link-blocks: offline contract tests. Edge direction, cross-repo edges, and the
# instance-setting refusal are driven through a mocked curl — no live Gitea call.
set -uo pipefail
S="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/link-blocks.sh"
D="$(dirname "$S")"
source "$D/../../lib/verb-test-helpers.sh"
# shellcheck source=mock.sh
source "$D/mock.sh"

# --- offline usage errors (no network) ---
assert_help "$S"
assert_usage_error "$S" --nope
assert_usage_error "$S"                                     # no id
assert_usage_error "$S" "gitea:acme/webapp#12"              # no --blocked-by
assert_usage_error "$S" "gitea:acme/webapp#12" --blocked-by # flag without value
assert_usage_error "$S" "not-an-id" --blocked-by "gitea:acme/webapp#4"
assert_usage_error "$S" "gitea:acme/webapp#12" --blocked-by "not-an-id"
assert_usage_error "$S" "github:o/r#1" --blocked-by "gitea:acme/webapp#4"
# An item cannot block itself. Gitea rejects the self-edge too, but catching it here
# keeps the diagnostic about the request rather than about the provider's error text.
assert_usage_error "$S" "gitea:acme/webapp#12" --blocked-by "gitea:acme/webapp#12"

gitea_fixture_init
trap 'rm -rf "$GITEA_FIX"' EXIT

# --- both ends face the authorization boundary ---
rc="$(gitea_run "$S" "gitea:other/repo#1" --blocked-by "gitea:acme/webapp#4")"
assert_eq "out-of-scope target → exit 2" "2" "$rc"
assert_eq "nothing was requested" "" "$(gitea_requests)"
rc="$(gitea_run "$S" "gitea:acme/webapp#12" --blocked-by "gitea:other/repo#4")"
assert_eq "out-of-scope blocker → exit 2" "2" "$rc"
assert_contains "the refusal names the blocker repo" "$(gitea_err)" "other/repo"
assert_eq "still nothing requested" "" "$(gitea_requests)"

# --- happy path: direction matters ---
# Gitea documents POST /issues/{index}/dependencies as "make the issue in the url
# depend on the issue in the form", so the URL carries the BLOCKED item and the body
# carries the BLOCKER. Getting this backwards would invert every dependency edge, and
# the frontier would then release exactly the items it should hold.
gitea_reset_routes
gitea_seed "/dependencies" 201 "$(gitea_issue_json 4 open 'the blocker')"
rc="$(gitea_run "$S" "gitea:acme/webapp#12" --blocked-by "gitea:acme/webapp#4")"
assert_eq "link → exit 0" "0" "$rc"
assert_eq "schema_version" "1.0" "$(jq -r '.schema_version' <<<"$(gitea_out)")"
assert_eq "id is the blocked item" "gitea:acme/webapp#12" "$(jq -r '.id' <<<"$(gitea_out)")"
assert_eq "blocked_by is the blocker" "gitea:acme/webapp#4" "$(jq -r '.blocked_by' <<<"$(gitea_out)")"
assert_eq "linked" "true" "$(jq -r '.linked' <<<"$(gitea_out)")"
# The BLOCKED item's number is in the URL — not the blocker's.
assert_contains "the blocked item is the URL subject" "$(gitea_requests)" \
  "POST https://git.example.invalid/api/v1/repos/acme/webapp/issues/12/dependencies"

# --- cross-repository edges ---
# Gitea's IssueMeta carries owner and repo, so a blocker may live in another declared
# repository (features.cross_repo_edges=true).
gitea_write_binding '{"scopes":["acme/webapp","acme/api"]}'
gitea_reset_routes
gitea_seed "/dependencies" 201 "$(gitea_issue_json 7 open 'cross-repo blocker')"
rc="$(gitea_run "$S" "gitea:acme/webapp#12" --blocked-by "gitea:acme/api#7")"
assert_eq "cross-repo link → exit 0" "0" "$rc"
assert_eq "blocked_by names the other repo" "gitea:acme/api#7" "$(jq -r '.blocked_by' <<<"$(gitea_out)")"

# An instance with ALLOW_CROSS_REPOSITORY_DEPENDENCIES off answers 400 with that exact
# message. It is an instance configuration fact, not a malformed request, so the
# diagnostic must point the operator at the setting.
gitea_reset_routes
gitea_seed "/dependencies" 400 '{"message":"CrossRepositoryDependencies not enabled"}'
rc="$(gitea_run "$S" "gitea:acme/webapp#12" --blocked-by "gitea:acme/api#7")"
assert_eq "cross-repo disabled → exit 7" "7" "$rc"
assert_contains "the instance setting is named" "$(gitea_err)" "ALLOW_CROSS_REPOSITORY_DEPENDENCIES"
gitea_write_binding

# --- HTTP status mapping ---
gitea_reset_routes
gitea_seed "/dependencies" 404 '{"message":"the issue does not exist"}'
rc="$(gitea_run "$S" "gitea:acme/webapp#12" --blocked-by "gitea:acme/webapp#4")"
assert_eq "missing issue → exit 5" "5" "$rc"

gitea_reset_routes
gitea_seed "/dependencies" 423 '{"message":"repo is archived"}'
rc="$(gitea_run "$S" "gitea:acme/webapp#12" --blocked-by "gitea:acme/webapp#4")"
assert_eq "archived repo → exit 7" "7" "$rc"

[[ $FAILED -eq 0 ]] || exit 1
