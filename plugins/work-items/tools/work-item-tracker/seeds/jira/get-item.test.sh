#!/usr/bin/env bash
# shellcheck disable=SC2154  # FAILED/CASE_NUM initialized by the sourced helper
set -uo pipefail
S="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/get-item.sh"
source "$(dirname "$S")/../../lib/verb-test-helpers.sh"
# shellcheck source=mock.sh
source "$(dirname "$S")/mock.sh"

assert_help "$S"
assert_usage_error "$S" --nope
assert_usage_error "$S"
assert_usage_error "$S" "not-an-id"
assert_usage_error "$S" "github:o/r#1"

jira_fixture_init
trap 'rm -rf "$JIRA_FIX"' EXIT
jira_write_binding '["SW2"]'

cat >"$JIRA_FIX/1.body" <<'JSON'
{"key":"SW2-12345","fields":{"summary":"Do the thing","status":{"statusCategory":{"key":"indeterminate"}},"assignee":{"accountId":"acc-1"},"labels":["backend","urgent"],"issuetype":{"name":"Task"},"parent":{"key":"SW2-100"},"issuelinks":[{"type":{"name":"Blocks"},"inwardIssue":{"key":"SW2-9","fields":{"status":{"statusCategory":{"key":"new"}}}}},{"type":{"name":"Blocks"},"inwardIssue":{"key":"SW2-8","fields":{"status":{"statusCategory":{"key":"done"}}}}}]}}
JSON
printf '200' >"$JIRA_FIX/1.status"

jira_run "$S" "jira:test.atlassian.net/SW2#12345"
assert_eq "get-item happy path exit 0" "0" "$RC"
assert_eq "schema_version" "1.0" "$(jq -r '.schema_version' <<<"$OUT")"
assert_eq "id qualified" "jira:test.atlassian.net/SW2#12345" "$(jq -r '.id' <<<"$OUT")"
assert_eq "title" "Do the thing" "$(jq -r '.title' <<<"$OUT")"
assert_eq "state open (indeterminate)" "open" "$(jq -r '.state' <<<"$OUT")"
assert_eq "assignee accountId" "acc-1" "$(jq -r '.assignees[0]' <<<"$OUT")"
assert_eq "labels verbatim" "backend,urgent" "$(jq -r '.labels | join(",")' <<<"$OUT")"
assert_eq "type name" "Task" "$(jq -r '.type' <<<"$OUT")"
assert_eq "parent_id qualified" "jira:test.atlassian.net/SW2#100" "$(jq -r '.parent_id' <<<"$OUT")"
assert_eq "url is browse link" "https://test.atlassian.net/browse/SW2-12345" "$(jq -r '.url' <<<"$OUT")"
case "$OUT" in *$'\r'*) fail "stdout CR-free" "no CR" "CR present" ;; *) pass "stdout CR-free" ;; esac
assert_eq "no resolutions key → no resolution lookup" "1" "$(cat "$JIRA_FIX/.counter")"
assert_eq "no resolutions key → the done blocker is resolved" "1" "$(jq -r '.blocked_by_count' <<<"$OUT")"
assert_eq "no resolutions key → won't-do count 0" "0" "$(jq -r '.blocked_by_wont_do_count' <<<"$OUT")"

jira_write_binding '["SW2"]' '{"resolutions":{"completed":["10000"],"wont_do":["10001"]}}'
with_lookup() {
  printf '%s' "$1" >"$JIRA_FIX/2.body"
  printf '%s' "$2" >"$JIRA_FIX/2.status"
  jira_run "$S" "jira:test.atlassian.net/SW2#12345"
}
with_lookup '{"issues":[{"key":"SW2-8","fields":{"resolution":{"id":"10000","name":"Done"}}}]}' 200
assert_eq "completed id → exit 0" "0" "$RC"
assert_eq "completed id → the done blocker is resolved" "1" "$(jq -r '.blocked_by_count' <<<"$OUT")"
assert_eq "completed id → won't-do count 0" "0" "$(jq -r '.blocked_by_wont_do_count' <<<"$OUT")"
lookup="$(awk '/^--data$/{getline; print; exit}' "$JIRA_FIX/2.args")"
assert_eq "resolution lookup JQL names only the done blocker" 'key in ("SW2-8")' "$(jq -r '.jql' <<<"$lookup")"
assert_eq "resolution lookup asks for the resolution field" '["resolution"]' "$(jq -c '.fields' <<<"$lookup")"

with_lookup '{"issues":[{"key":"SW2-8","fields":{"resolution":{"id":"10001","name":"Will Not Do"}}}]}' 200
assert_eq "wont_do id → the done blocker keeps blocking" "2" "$(jq -r '.blocked_by_count' <<<"$OUT")"
assert_eq "wont_do id → counted as won't-do" "1" "$(jq -r '.blocked_by_wont_do_count' <<<"$OUT")"

with_lookup '{"issues":[{"key":"SW2-8","fields":{"resolution":{"id":"10000","name":"Will Not Do"}}}]}' 200
assert_eq "a completed id renamed Will Not Do is resolved" "1" "$(jq -r '.blocked_by_count' <<<"$OUT")"

with_lookup '{"issues":[{"key":"SW2-8","fields":{"resolution":null}}]}' 200
assert_eq "null resolution → resolved" "1" "$(jq -r '.blocked_by_count' <<<"$OUT")"
assert_eq "null resolution → won't-do count 0" "0" "$(jq -r '.blocked_by_wont_do_count' <<<"$OUT")"

with_lookup '{"issues":[{"key":"SW2-8","fields":{"resolution":{"id":"10099","name":"Abandoned"}}}]}' 200
assert_eq "unclassified id → exit 0" "0" "$RC"
assert_eq "unclassified id → the done blocker keeps blocking" "2" "$(jq -r '.blocked_by_count' <<<"$OUT")"
assert_eq "unclassified id → not won't-do" "0" "$(jq -r '.blocked_by_wont_do_count' <<<"$OUT")"
assert_contains "unclassified id → stderr names the resolution" "$ERR" "Abandoned"
assert_contains "unclassified id → stderr names the id" "$ERR" "10099"

with_lookup '{"errorMessages":["boom"]}' 500
assert_eq "failed lookup still exits 0" "0" "$RC"
assert_eq "failed lookup keeps the done blocker blocking" "2" "$(jq -r '.blocked_by_count' <<<"$OUT")"
assert_eq "failed lookup counts no won't-do" "0" "$(jq -r '.blocked_by_wont_do_count' <<<"$OUT")"
assert_contains "failed lookup warns on stderr" "$ERR" "resolution query failed"
with_lookup '{"issues":[]}' 200
assert_eq "a blocker the lookup did not return keeps blocking" "2" "$(jq -r '.blocked_by_count' <<<"$OUT")"
assert_eq "a blocker the lookup did not return is not won't-do" "0" "$(jq -r '.blocked_by_wont_do_count' <<<"$OUT")"
assert_contains "a blocker the lookup did not return is named on stderr" "$ERR" "SW2-8"

for bad in 'null' '"10001"' '["10001"]' '{"wont_do":["10001"]}' '{"completed":["10000"],"wont_do":[""]}' \
  '{"completed":["10000"],"wont_do":[10001]}' '{"completed":["10001"],"wont_do":["10001"]}' \
  '{"completed":[],"wont_do":[],"other":[]}'; do
  jira_write_binding '["SW2"]' "{\"resolutions\":$bad}"
  jira_run "$S" "jira:test.atlassian.net/SW2#12345"
  assert_eq "malformed resolutions $bad → config (3)" "3" "$RC"
done

jira_write_binding '["SW2"]' '{"resolutions":{"completed":["10000"],"wont_do":["10001"]}}'
cat >"$JIRA_FIX/1.body" <<'JSON'
{"key":"SW2-12346","fields":{"summary":"Cross-project","status":{"statusCategory":{"key":"new"}},"assignee":null,"labels":[],"issuetype":{"name":"Task"},"parent":null,"issuelinks":[{"type":{"name":"Blocks"},"inwardIssue":{"key":"OTHER-3","fields":{"status":{"statusCategory":{"key":"done"}}}}}]}}
JSON
jira_run "$S" "jira:test.atlassian.net/SW2#12346"
assert_eq "out-of-scope done blocker makes no lookup" "1" "$(cat "$JIRA_FIX/.counter")"
assert_eq "out-of-scope done blocker is resolved" "0" "$(jq -r '.blocked_by_count' <<<"$OUT")"
rm -f "$JIRA_FIX/2.body" "$JIRA_FIX/2.status"
jira_write_binding '["SW2"]'

cat >"$JIRA_FIX/1.body" <<'JSON'
{"key":"SW2-7","fields":{"summary":"Shipped","status":{"statusCategory":{"key":"done"}},"assignee":null,"labels":[],"issuetype":{"name":"Bug"},"parent":null,"issuelinks":[]}}
JSON
printf '200' >"$JIRA_FIX/1.status"
jira_run "$S" "jira:test.atlassian.net/SW2#7"
assert_eq "done-category → closed" "closed" "$(jq -r '.state' <<<"$OUT")"
assert_eq "no assignee → empty array" "0" "$(jq -r '.assignees | length' <<<"$OUT")"
assert_eq "no parent → null" "null" "$(jq -r '.parent_id' <<<"$OUT")"

# An assignee object present but with a null accountId (a privacy-restricted user)
# projects to an empty assignees array, not [null] — the frontier keys on emptiness.
cat >"$JIRA_FIX/1.body" <<'JSON'
{"key":"SW2-6","fields":{"summary":"Restricted","status":{"statusCategory":{"key":"new"}},"assignee":{"accountId":null},"labels":[],"issuetype":{"name":"Task"},"parent":null,"issuelinks":[]}}
JSON
printf '200' >"$JIRA_FIX/1.status"
jira_run "$S" "jira:test.atlassian.net/SW2#6"
assert_eq "assignee with null accountId → empty array" "0" "$(jq -r '.assignees | length' <<<"$OUT")"

jira_run "$S" "jira:other.atlassian.net/SW2#1"
assert_eq "cross-site id → usage (2)" "2" "$RC"

jira_run "$S" "jira:test.atlassian.net/SW.2#1"
assert_eq "malformed project key in id → usage (2)" "2" "$RC"
if [[ ! -e "$JIRA_FIX/.counter" ]]; then
  pass "malformed key made no HTTP call"
else
  fail "malformed key made no HTTP call" "no curl call" "curl invoked"
fi

# A well-formed id for a project NOT in the binding's project_keys (binding declares
# only SW2) must be refused before any fetch — reads are bounded to the declared scope.
jira_run "$S" "jira:test.atlassian.net/OTHER#1"
assert_eq "out-of-scope project id → usage (2)" "2" "$RC"
if [[ ! -e "$JIRA_FIX/.counter" ]]; then
  pass "out-of-scope id made no HTTP call"
else
  fail "out-of-scope id made no HTTP call" "no curl call" "curl invoked"
fi

printf '404' >"$JIRA_FIX/1.status"
printf '{"errorMessages":["Issue does not exist"]}' >"$JIRA_FIX/1.body"
jira_run "$S" "jira:test.atlassian.net/SW2#999"
assert_eq "404 → not-found (5)" "5" "$RC"

printf '200' >"$JIRA_FIX/1.status"
printf '{"errorMessages":["boom"]}' >"$JIRA_FIX/1.body"
jira_run "$S" "jira:test.atlassian.net/SW2#5"
assert_eq "2xx without issue key → unavailable (8)" "8" "$RC"

printf '200' >"$JIRA_FIX/1.status"
printf '{"key":"NOT A JIRA KEY","fields":{"summary":"x","status":{"statusCategory":{"key":"new"}},"assignee":null,"labels":[],"issuetype":{"name":"Task"},"parent":null,"issuelinks":[]}}' >"$JIRA_FIX/1.body"
jira_run "$S" "jira:test.atlassian.net/SW2#5"
assert_eq "un-normalizable issue key → unavailable (8)" "8" "$RC"

WORK_ITEM_TRACKER_BINDING="$JIRA_FIX/binding.json" WIT_JIRA_CURL="$JIRA_FIX/curl" \
  bash "$S" "jira:test.atlassian.net/SW2#1" >/dev/null 2>&1
assert_eq "unset token env → auth (4)" "4" "$?"

jq -cn '{schema_version:"1.0", provider:"jira",
  config:{lease_ttl_hours:24, jira:{site:"test.atlassian.net", auth_email:"x@y", auth_env:"JIRA_TEST_TOKEN"}}}' >"$JIRA_FIX/bad-binding.json"
WORK_ITEM_TRACKER_BINDING="$JIRA_FIX/bad-binding.json" WIT_JIRA_CURL="$JIRA_FIX/curl" \
  JIRA_TEST_TOKEN="dummy" bash "$S" "jira:test.atlassian.net/SW2#1" >/dev/null 2>&1
assert_eq "missing project_keys → config (3)" "3" "$?"

[[ $FAILED -eq 0 ]] || exit 1
