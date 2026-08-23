#!/usr/bin/env bash
# shellcheck disable=SC2154  # FAILED/CASE_NUM initialized by the sourced helper
# get-item: offline contract tests. The happy path drives the REAL normalizer against a
# canned Gitea issue through a mocked curl — no live Gitea call.
set -uo pipefail
S="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/get-item.sh"
D="$(dirname "$S")"
source "$D/../../lib/verb-test-helpers.sh"
# shellcheck source=mock.sh
source "$D/mock.sh"

# --- offline usage / config errors (no network) ---
assert_help "$S"
assert_usage_error "$S" --nope
assert_usage_error "$S" # no id
assert_usage_error "$S" "not-an-id"
assert_usage_error "$S" "#12"
# Well-formed grammar, wrong provider → rejected before any I/O.
assert_usage_error "$S" "github:o/r#1"
assert_usage_error "$S" "gitea:acme/webapp#12" extra

gitea_fixture_init
trap 'rm -rf "$GITEA_FIX"' EXIT

# --- the declared scope is an authorization boundary, not a filter ---
rc="$(gitea_run "$S" "gitea:other/repo#5")"
assert_eq "an undeclared repo is refused → exit 2" "2" "$rc"
assert_contains "the refusal names config.gitea.scopes" "$(gitea_err)" "config.gitea.scopes"
assert_eq "and no request was made" "" "$(gitea_requests)"

# --- happy path ---
gitea_reset_routes
gitea_seed "/dependencies" 200 '[]'
gitea_seed "/issues/12" 200 "$(gitea_issue_json 12 open 'a real issue')"

rc="$(gitea_run "$S" "gitea:acme/webapp#12")"
assert_eq "get-item exit 0" "0" "$rc"
assert_eq "schema_version" "1.0" "$(jq -r '.schema_version' <<<"$(gitea_out)")"
# The ID is rebuilt from the payload, not echoed from the argument — a normalizer that
# silently dropped `number` would still look right if the argument were echoed.
assert_eq "id is fully qualified" "gitea:acme/webapp#12" "$(jq -r '.id' <<<"$(gitea_out)")"
assert_eq "title" "a real issue" "$(jq -r '.title' <<<"$(gitea_out)")"
assert_eq "state normalized" "open" "$(jq -r '.state' <<<"$(gitea_out)")"
assert_eq "assignees are logins" "kyle" "$(jq -r '.assignees[0]' <<<"$(gitea_out)")"
assert_eq "labels are names" "type: fix" "$(jq -r '.labels[0]' <<<"$(gitea_out)")"
assert_eq "url" "https://git.example.invalid/acme/webapp/issues/12" "$(jq -r '.url' <<<"$(gitea_out)")"
# Gitea has no issue-type registry and no parent field, so these are structurally null
# for this provider — not "unmapped".
assert_eq "type is null (gitea has no type axis)" "null" "$(jq -r '.type' <<<"$(gitea_out)")"
assert_eq "parent_id is null (gitea has no sub-item link)" "null" "$(jq -r '.parent_id' <<<"$(gitea_out)")"
# The seam's normalized object has no body field, whatever the provider returns.
assert_eq "body is not carried through the seam" "null" "$(jq -r '.body' <<<"$(gitea_out)")"

# --- state normalization ---
gitea_reset_routes
gitea_seed "/dependencies" 200 '[]'
gitea_seed "/issues/12" 200 "$(gitea_issue_json 12 closed 'done one')"
rc="$(gitea_run "$S" "gitea:acme/webapp#12")"
assert_eq "closed issue → exit 0" "0" "$rc"
assert_eq "closed state normalized" "closed" "$(jq -r '.state' <<<"$(gitea_out)")"

# --- blocked_by_count counts OPEN blockers only ---
# Counting closed blockers is the bug that keeps an item off the frontier forever: the
# blocker is resolved, but the item never becomes eligible.
gitea_reset_routes
gitea_seed "/dependencies" 200 "$(jq -cn '[{number:1,state:"open"},{number:2,state:"closed"},{number:3,state:"open"}]')"
gitea_seed "/issues/12" 200 "$(gitea_issue_json 12 open 'blocked one')"
rc="$(gitea_run "$S" "gitea:acme/webapp#12")"
assert_eq "blocked issue → exit 0" "0" "$rc"
assert_eq "blocked_by_count counts only open blockers" "2" "$(jq -r '.blocked_by_count' <<<"$(gitea_out)")"

# A repo with the dependencies unit disabled answers 404 on that endpoint while the
# issue itself exists. That must read as "no visible edges", never as a missing ITEM.
gitea_reset_routes
gitea_seed "/dependencies" 404 '{"message":"issue dependencies are not enabled"}'
gitea_seed "/issues/12" 200 "$(gitea_issue_json 12 open 'deps disabled')"
rc="$(gitea_run "$S" "gitea:acme/webapp#12")"
assert_eq "dependencies unit disabled still returns the item" "0" "$rc"
assert_eq "and reports zero blockers" "0" "$(jq -r '.blocked_by_count' <<<"$(gitea_out)")"

# A dependencies request that fails for any OTHER reason is not "no visible edges": the
# count is unknown, and reporting 0 would put a blocked item on the frontier. The status
# cases below fail the ISSUE fetch and never reach the count, so these seed a healthy
# issue and break only the second request — the shape that once let the failure exit
# inside $( ) and the verb carry on.
gitea_reset_routes
gitea_seed "/dependencies" 401 '{"message":"token required"}'
gitea_seed "/issues/12" 200 "$(gitea_issue_json 12 open 'issue ok, deps refused')"
rc="$(gitea_run "$S" "gitea:acme/webapp#12")"
assert_eq "unauthorized dependencies read → exit 4, not the count's absence" "4" "$rc"
assert_eq "and no item is emitted" "" "$(gitea_out)"

# 8 in particular has to survive: work-loop routes "seam exit 8 → backoff-and-retry", so
# a 5xx that collapses to 1 never triggers the backoff it was raised for.
gitea_reset_routes
gitea_seed "/dependencies" 503 '{"message":"down"}'
gitea_seed "/issues/12" 200 "$(gitea_issue_json 12 open 'issue ok, deps down')"
rc="$(gitea_run "$S" "gitea:acme/webapp#12")"
assert_eq "unavailable dependencies read → exit 8" "8" "$rc"

# --- HTTP status mapping ---
gitea_reset_routes
gitea_seed "/issues/12" 404 '{"message":"issue does not exist"}'
rc="$(gitea_run "$S" "gitea:acme/webapp#12")"
assert_eq "missing issue → exit 5" "5" "$rc"

gitea_reset_routes
gitea_seed "/issues/12" 401 '{"message":"token required"}'
rc="$(gitea_run "$S" "gitea:acme/webapp#12")"
assert_eq "unauthenticated → exit 4" "4" "$rc"

gitea_reset_routes
gitea_seed "/issues/12" 503 '{"message":"down"}'
rc="$(gitea_run "$S" "gitea:acme/webapp#12")"
assert_eq "server error → exit 8" "8" "$rc"

# --- the credential never reaches argv, on a real verb path ---
# common.test.sh proves this for the transport helper; this proves the verb actually
# uses that helper rather than building its own request.
gitea_reset_routes
gitea_seed "/dependencies" 200 '[]'
gitea_seed "/issues/12" 200 "$(gitea_issue_json 12 open 'x')"
gitea_run "$S" "gitea:acme/webapp#12" >/dev/null
assert_contains "the verb requested the issue over https" "$(gitea_requests)" \
  "GET https://git.example.invalid/api/v1/repos/acme/webapp/issues/12"

[[ $FAILED -eq 0 ]] || exit 1
