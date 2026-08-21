#!/usr/bin/env bash
# shellcheck disable=SC2154  # FAILED/CASE_NUM initialized by the sourced helper
# list-items: offline contract tests. Pagination, PR exclusion, and the per-item
# blocker count are all driven through a mocked curl — no live Gitea call.
set -uo pipefail
S="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/list-items.sh"
D="$(dirname "$S")"
source "$D/../../lib/verb-test-helpers.sh"
# shellcheck source=mock.sh
source "$D/mock.sh"

# --- offline usage errors (no network) ---
assert_help "$S"
assert_usage_error "$S" --nope
assert_usage_error "$S" --state
assert_usage_error "$S" --state sideways
assert_usage_error "$S" --repo

gitea_fixture_init
trap 'rm -rf "$GITEA_FIX"' EXIT

# --repo is caller text that reaches a request path, so it faces the same anchored
# allowlist the binding's own scopes did.
rc="$(gitea_run "$S" --repo "not-a-scope")"
assert_eq "malformed --repo → exit 2" "2" "$rc"
rc="$(gitea_run "$S" --repo "../../etc/passwd")"
assert_eq "traversing --repo → exit 2" "2" "$rc"
assert_eq "and nothing was requested" "" "$(gitea_requests)"

rc="$(gitea_run "$S" --repo "other/repo")"
assert_eq "undeclared --repo → exit 2" "2" "$rc"
assert_contains "refusal names the declared scope list" "$(gitea_err)" "config.gitea.scopes"

# --- the single declared scope is the default target ---
gitea_reset_routes
gitea_seed "/dependencies" 200 '[]'
gitea_seed "/issues?" 200 "[$(gitea_issue_json 12 open 'one')]"
rc="$(gitea_run "$S")"
assert_eq "no --repo with one declared scope → exit 0" "0" "$rc"
assert_eq "envelope schema_version" "1.0" "$(jq -r '.schema_version' <<<"$(gitea_out)")"
assert_eq "one item" "1" "$(jq -r '.items | length' <<<"$(gitea_out)")"
assert_eq "item id is fully qualified" "gitea:acme/webapp#12" "$(jq -r '.items[0].id' <<<"$(gitea_out)")"
# The page size must be EXPLICIT. Gitea defaults an omitted limit to 30 and truncates
# silently — the same trap the contract calls out for `gh`.
assert_contains "the request sends an explicit limit" "$(gitea_requests)" "limit=50"
assert_contains "the request sends the requested state" "$(gitea_requests)" "state=open"

# With two declared scopes the target is ambiguous. Picking the first would quietly
# list the wrong repository, so it is a usage error naming the fix.
gitea_write_binding '{"scopes":["acme/webapp","acme/api"]}'
gitea_reset_routes
rc="$(gitea_run "$S")"
assert_eq "no --repo with two declared scopes → exit 2" "2" "$rc"
assert_contains "and says --repo is required" "$(gitea_err)" "--repo is required"
assert_eq "nothing was requested" "" "$(gitea_requests)"
gitea_write_binding

# --- pull requests are excluded ---
# In Gitea a PR IS an issue with `pull_request` populated. A PR arriving as a work item
# would be claimed and worked like one.
gitea_reset_routes
gitea_seed "/dependencies" 200 '[]'
gitea_seed "/issues?" 200 "$(jq -cn --argjson i "$(gitea_issue_json 12 open 'real issue')" \
  '[$i, ($i | .number = 13 | .title = "a pull request" | .pull_request = {merged:false})]')"
rc="$(gitea_run "$S")"
assert_eq "mixed issue/PR page → exit 0" "0" "$rc"
assert_eq "the pull request is dropped" "1" "$(jq -r '.items | length' <<<"$(gitea_out)")"
assert_eq "the issue survives" "gitea:acme/webapp#12" "$(jq -r '.items[0].id' <<<"$(gitea_out)")"

# --- blocker counts are per item, and count OPEN blockers only ---
gitea_reset_routes
gitea_seed "/issues/12/dependencies" 200 "$(jq -cn '[{number:1,state:"open"},{number:2,state:"closed"}]')"
gitea_seed "/dependencies" 200 '[]'
gitea_seed "/issues?" 200 "[$(gitea_issue_json 12 open 'blocked')]"
rc="$(gitea_run "$S")"
assert_eq "blocked item listed → exit 0" "0" "$rc"
assert_eq "blocked_by_count is per item and open-only" "1" "$(jq -r '.items[0].blocked_by_count' <<<"$(gitea_out)")"

# --- an empty repository is an empty envelope, never an error ---
gitea_reset_routes
gitea_seed "/issues?" 200 '[]'
rc="$(gitea_run "$S")"
assert_eq "empty repo → exit 0" "0" "$rc"
assert_eq "empty items array" "0" "$(jq -r '.items | length' <<<"$(gitea_out)")"

# --- pagination stops on a short page ---
# Gitea sends no total-count header on this endpoint, so a short page is the only
# end-of-list signal. With page_size 2, a 2-row page must be followed by another
# request and a 1-row page must not.
gitea_write_binding '{"page_size":2}'
gitea_reset_routes
gitea_seed "/dependencies" 200 '[]'
gitea_seed "page=2" 200 "[$(gitea_issue_json 14 open 'third')]"
gitea_seed "page=1" 200 "$(jq -cn --argjson i "$(gitea_issue_json 12 open 'first')" \
  '[$i, ($i | .number = 13 | .title = "second")]')"
rc="$(gitea_run "$S")"
assert_eq "paged listing → exit 0" "0" "$rc"
assert_eq "all three items collected across pages" "3" "$(jq -r '.items | length' <<<"$(gitea_out)")"
assert_contains "a second page was requested" "$(gitea_requests)" "page=2"
assert_contains "the configured page size is honored" "$(gitea_requests)" "limit=2"
# A third page must NOT be requested: page 2 came back short.
if [[ "$(gitea_requests)" == *"page=3"* ]]; then
  fail "pagination stops on a short page" "no page=3" "page=3 requested"
else
  pass "pagination stops on a short page"
fi
gitea_write_binding

# --- a failing per-item blocker count keeps its own status ---
# The status cases below fail the ISSUE page and never reach the per-item count. These
# seed a healthy page and break only the dependencies request, so the failure is the one
# that used to exit inside $( ) and reach the caller as this adapter's internal error.
gitea_reset_routes
gitea_seed "/dependencies" 401 '{"message":"token required"}'
gitea_seed "/issues?" 200 "[$(gitea_issue_json 12 open 'listed')]"
rc="$(gitea_run "$S")"
assert_eq "unauthorized dependencies read → exit 4" "4" "$rc"
assert_eq "and no envelope is emitted" "" "$(gitea_out)"

# work-loop routes "seam exit 8 → backoff-and-retry", so a 5xx here must stay an 8.
gitea_reset_routes
gitea_seed "/dependencies" 503 '{"message":"down"}'
gitea_seed "/issues?" 200 "[$(gitea_issue_json 12 open 'listed')]"
rc="$(gitea_run "$S")"
assert_eq "unavailable dependencies read → exit 8" "8" "$rc"

# --- HTTP status mapping ---
gitea_reset_routes
gitea_seed "/issues?" 404 '{"message":"repo not found"}'
rc="$(gitea_run "$S")"
assert_eq "missing repo → exit 5" "5" "$rc"

gitea_reset_routes
gitea_seed "/issues?" 429 '{"message":"slow down"}'
rc="$(gitea_run "$S")"
assert_eq "rate limited → exit 8" "8" "$rc"

[[ $FAILED -eq 0 ]] || exit 1
