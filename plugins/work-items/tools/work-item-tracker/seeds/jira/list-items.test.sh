#!/usr/bin/env bash
# shellcheck disable=SC2154  # FAILED/CASE_NUM initialized by the sourced helper
# test-scope: plugins/work-items/tools/work-item-tracker/seeds/jira/* plugins/work-items/tools/work-item-tracker/lib/*
set -uo pipefail
S="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/list-items.sh"
source "$(dirname "$S")/../../lib/verb-test-helpers.sh"
# shellcheck source=mock.sh
source "$(dirname "$S")/mock.sh"

assert_help "$S"
assert_usage_error "$S" --state bogus
assert_usage_error "$S" --unknown-flag

jira_fixture_init
trap 'rm -rf "$JIRA_FIX"' EXIT
jira_write_binding '["SW2","ABC"]'

sent_jql() {
  local data
  data="$(awk '/^--data$/{getline; print; exit}' "$JIRA_FIX/$1.args")"
  jq -r '.jql' <<<"$data"
}

cat >"$JIRA_FIX/1.body" <<'JSON'
{"issues":[{"key":"SW2-1","fields":{"summary":"First","status":{"statusCategory":{"key":"new"}},"assignee":null,"labels":["a"],"issuetype":{"name":"Task"},"parent":null,"issuelinks":[],"created":"2026-01-02T03:04:05.000-0500"}}],"nextPageToken":"tok-2","isLast":false}
JSON
printf '200' >"$JIRA_FIX/1.status"
cat >"$JIRA_FIX/2.body" <<'JSON'
{"issues":[{"key":"ABC-42","fields":{"summary":"Second","status":{"statusCategory":{"key":"indeterminate"}},"assignee":{"accountId":"acc-9"},"labels":[],"issuetype":{"name":"Story"},"parent":{"key":"ABC-1"},"issuelinks":[{"type":{"name":"Blocks"},"inwardIssue":{"key":"ABC-5","fields":{"status":{"statusCategory":{"key":"new"}}}}}]}}],"nextPageToken":null,"isLast":true}
JSON
printf '200' >"$JIRA_FIX/2.status"

jira_run "$S" --state open
assert_eq "list-items exit 0" "0" "$RC"
assert_eq "schema_version" "1.0" "$(jq -r '.schema_version' <<<"$OUT")"
assert_eq "paginated across 2 pages → 2 items" "2" "$(jq -r '.items | length' <<<"$OUT")"
assert_eq "mock curl called twice" "2" "$(cat "$JIRA_FIX/.counter")"
assert_eq "a walk that reached the last page carries truncated:false" "false" "$(jq -c '.truncated' <<<"$OUT")"
assert_eq "page-1 item id" "jira:test.atlassian.net/SW2#1" "$(jq -r '.items[0].id' <<<"$OUT")"
assert_eq "page-2 item id" "jira:test.atlassian.net/ABC#42" "$(jq -r '.items[1].id' <<<"$OUT")"
assert_eq "page-2 item blocked_by_count" "1" "$(jq -r '.items[1].blocked_by_count' <<<"$OUT")"
assert_eq "page-2 item parent qualified" "jira:test.atlassian.net/ABC#1" "$(jq -r '.items[1].parent_id' <<<"$OUT")"
assert_eq "created (local offset) becomes UTC created_at" "2026-01-02T08:04:05Z" "$(jq -r '.items[0].created_at' <<<"$OUT")"
assert_eq "an issue without created reads created_at null" "null" "$(jq -c '.items[1].created_at' <<<"$OUT")"
assert_eq "a row carries milestone as null" "true" "$(jq -c '.items[0] | has("milestone") and .milestone == null' <<<"$OUT")"
assert_contains "the search asks for created" \
  "$(awk '/^--data$/{getline; print; exit}' "$JIRA_FIX/1.args" | jq -c '.fields')" '"created"'
case "$OUT" in *$'\r'*) fail "stdout CR-free" "no CR" "CR present" ;; *) pass "stdout CR-free" ;; esac

assert_eq "open-state JQL scopes projects + excludes done" \
  'project in ("SW2","ABC") AND statusCategory not in ("done","completed") ORDER BY created ASC' \
  "$(sent_jql 1)"

rm -f "$JIRA_FIX/2.body" "$JIRA_FIX/2.status"
printf '{"issues":[],"nextPageToken":null,"isLast":true}' >"$JIRA_FIX/1.body"
printf '200' >"$JIRA_FIX/1.status"
jira_run "$S" --repo "test.atlassian.net/ABC" --state all
assert_eq "--repo scopes to one project" 'project in ("ABC") ORDER BY created ASC' "$(sent_jql 1)"

# --label narrows the search, so the ceiling counts labeled issues only (#7173).
jira_run "$S" --repo "test.atlassian.net/ABC" --state all --label "area:ci"
assert_eq "--label → exit 0" "0" "$RC"
assert_eq "--label adds a labels clause to the JQL" \
  'project in ("ABC") AND labels = "area:ci" ORDER BY created ASC' "$(sent_jql 1)"
jira_run "$S" --label 'x" OR labels is EMPTY OR labels = "y'
assert_eq "a label holding a quote → usage (2)" "2" "$RC"
if [[ ! -e "$JIRA_FIX/.counter" ]]; then
  pass "a quoted --label made no HTTP call"
else
  fail "a quoted --label made no HTTP call" "no curl call" "curl invoked"
fi
jira_run "$S" --label 'a\z'
assert_eq "a label holding a backslash → usage (2)" "2" "$RC"
jira_run "$S" --label "area: ci"
assert_eq "a label holding a space (no Jira label can) → exit 0" "0" "$RC"
assert_eq "and lists nothing, complete" '[] false' "$(jq -c '.items, .truncated' <<<"$OUT" | paste -sd' ' -)"
if [[ ! -e "$JIRA_FIX/.counter" ]]; then
  pass "a whitespace --label made no HTTP call"
else
  fail "a whitespace --label made no HTTP call" "no curl call" "curl invoked"
fi

jira_run "$S" --repo "wrong.atlassian.net/SW2"
assert_eq "cross-site --repo → usage (2)" "2" "$RC"

# HOSTILE --repo project key with an embedded quote must be rejected before any JQL is
# built (exit 2), never break out of the `project in (...)` literal (JQL injection).
# jira_run clears .counter first; a rejection before any HTTP call leaves it absent.
jira_run "$S" --repo 'test.atlassian.net/SW2") OR (1=1) OR ("x'
assert_eq "injection --repo key → usage (2)" "2" "$RC"
if [[ ! -e "$JIRA_FIX/.counter" ]]; then
  pass "injection --repo made no HTTP call"
else
  fail "injection --repo made no HTTP call" "no curl call" "curl invoked"
fi

# --repo naming a well-formed project NOT in project_keys must be refused (exit 2):
# --repo narrows within the declared scope, it cannot widen to an undeclared project.
jira_run "$S" --repo "test.atlassian.net/OTHER"
assert_eq "out-of-scope --repo project → usage (2)" "2" "$RC"
if [[ ! -e "$JIRA_FIX/.counter" ]]; then
  pass "out-of-scope --repo made no HTTP call"
else
  fail "out-of-scope --repo made no HTTP call" "no curl call" "curl invoked"
fi

# rc_for_jira <case-label> <expected-rc> <jira-config-literal> — write a binding whose
# config.jira is the given jq object literal (jq syntax, interpolated into the jq
# program — not --argjson, which would demand strict JSON) and assert list-items
# --state open's exit code. Isolates the config-validation cases below.
rc_for_jira() {
  local label="$1" want="$2" jira="$3"
  rm -f "$JIRA_FIX/.counter"
  jq -cn "{schema_version:\"1.0\", provider:\"jira\", config:{lease_ttl_hours:24, jira:$jira}}" >"$JIRA_FIX/cfg-binding.json"
  WORK_ITEM_TRACKER_BINDING="$JIRA_FIX/cfg-binding.json" WIT_JIRA_CURL="$JIRA_FIX/curl" \
    JIRA_TEST_TOKEN="dummy" bash "$S" --state open >/dev/null 2>&1
  assert_eq "$label" "$want" "$?"
}

# HOSTILE config: a configured project key with an embedded quote is a config error
# (exit 3), caught at config load before any query is assembled.
rc_for_jira "injection project_keys config → config (3)" "3" \
  '{site:"test.atlassian.net", project_keys:["SW2\") OR (1=1) OR (\"x"], auth_email:"ci@test.example", auth_env:"JIRA_TEST_TOKEN"}'

rc_for_jira "non-array project_keys → config (3)" "3" \
  '{site:"test.atlassian.net", project_keys:"ABC", auth_email:"ci@test.example", auth_env:"JIRA_TEST_TOKEN"}'

# CREDENTIAL-EGRESS guard: site is the host the token is sent to. A site carrying URL
# structure, or a non-atlassian.net host without the explicit opt-in, is a config error
# (exit 3) BEFORE any request — a tracked binding cannot redirect the credential.
rc_for_jira "site with URL structure → config (3)" "3" \
  '{site:"evil.example/@x.atlassian.net", project_keys:["SW2"], auth_email:"a@b", auth_env:"JIRA_TEST_TOKEN"}'
rc_for_jira "non-atlassian site without opt-in → config (3)" "3" \
  '{site:"attacker.example", project_keys:["SW2"], auth_email:"a@b", auth_env:"JIRA_TEST_TOKEN"}'
printf '{"issues":[],"nextPageToken":null,"isLast":true}' >"$JIRA_FIX/1.body"
printf '200' >"$JIRA_FIX/1.status"
rc_for_jira "custom-domain opt-in accepted (not config error)" "0" \
  '{site:"jira.internal.example", project_keys:["SW2"], auth_email:"a@b", auth_env:"JIRA_TEST_TOKEN", allow_custom_domain:true}'

# auth_env must be a valid shell identifier — an invalid name aborts bash on the
# ${!name} deref, so reject it at config load (exit 3), not on first read.
rc_for_jira "invalid auth_env name → config (3)" "3" \
  '{site:"test.atlassian.net", project_keys:["SW2"], auth_email:"a@b", auth_env:"JIRA-TOKEN"}'

# An explicitly empty done_category_keys would build `statusCategory not in ()` (invalid
# JQL, HTTP 400) — reject it as a config error rather than surface a confusing exit 1.
rc_for_jira "empty done_category_keys → config (3)" "3" \
  '{site:"test.atlassian.net", project_keys:["SW2"], auth_email:"a@b", auth_env:"JIRA_TEST_TOKEN", done_category_keys:[]}'

# An array whose ELEMENT is empty (or non-string) must also be rejected — a bash
# line-loop would lose a trailing "" to command-substitution stripping, so validation
# runs in jq over every element. `[""]` in either key array → config error (exit 3).
rc_for_jira "empty-string done key element → config (3)" "3" \
  '{site:"test.atlassian.net", project_keys:["SW2"], auth_email:"a@b", auth_env:"JIRA_TEST_TOKEN", done_category_keys:[""]}'
rc_for_jira "empty-string project key element → config (3)" "3" \
  '{site:"test.atlassian.net", project_keys:[""], auth_email:"a@b", auth_env:"JIRA_TEST_TOKEN"}'
rc_for_jira "non-string project key element → config (3)" "3" \
  '{site:"test.atlassian.net", project_keys:[123], auth_email:"a@b", auth_env:"JIRA_TEST_TOKEN"}'
# A present-but-false/null done_category_keys must NOT silently collapse to the default
# (jq `//` would) — a typo'd override is a config error, not a filtering change.
rc_for_jira "false done_category_keys → config (3)" "3" \
  '{site:"test.atlassian.net", project_keys:["SW2"], auth_email:"a@b", auth_env:"JIRA_TEST_TOKEN", done_category_keys:false}'

rc_for_jira "empty blocked_by_link_type → config (3)" "3" \
  '{site:"test.atlassian.net", project_keys:["SW2"], auth_email:"a@b", auth_env:"JIRA_TEST_TOKEN", blocked_by_link_type:""}'
rc_for_jira "non-string blocked_by_link_type → config (3)" "3" \
  '{site:"test.atlassian.net", project_keys:["SW2"], auth_email:"a@b", auth_env:"JIRA_TEST_TOKEN", blocked_by_link_type:[]}'
printf '{"issues":[],"nextPageToken":null,"isLast":true}' >"$JIRA_FIX/1.body"
printf '200' >"$JIRA_FIX/1.status"
rc_for_jira "valid blocked_by_link_type accepted" "0" \
  '{site:"test.atlassian.net", project_keys:["SW2"], auth_email:"a@b", auth_env:"JIRA_TEST_TOKEN", blocked_by_link_type:"Blocked By"}'

jira_write_binding '["SW2","ABC"]' '{"resolutions":{"completed":["10000"],"wont_do":["10001"]}}'
cat >"$JIRA_FIX/1.body" <<'JSON'
{"issues":[{"key":"SW2-2","fields":{"summary":"Dependent","status":{"statusCategory":{"key":"new"}},"assignee":null,"labels":[],"issuetype":{"name":"Task"},"parent":null,"issuelinks":[{"type":{"name":"Blocks"},"inwardIssue":{"key":"ABC-7","fields":{"status":{"statusCategory":{"key":"done"}}}}}]}},{"key":"SW2-3","fields":{"summary":"Unblocked","status":{"statusCategory":{"key":"new"}},"assignee":null,"labels":[],"issuetype":{"name":"Task"},"parent":null,"issuelinks":[{"type":{"name":"Blocks"},"inwardIssue":{"key":"SW2-4","fields":{"status":{"statusCategory":{"key":"done"}}}}}]}}],"nextPageToken":null,"isLast":true}
JSON
printf '200' >"$JIRA_FIX/1.status"
printf '{"issues":[{"key":"ABC-7","fields":{"resolution":{"id":"10001","name":"Will Not Do"}}},{"key":"SW2-4","fields":{"resolution":{"id":"10000","name":"Done"}}}]}' >"$JIRA_FIX/2.body"
printf '200' >"$JIRA_FIX/2.status"
jira_run "$S" --state open
assert_eq "won't-do page exit 0" "0" "$RC"
assert_eq "one search plus one resolution lookup" "2" "$(cat "$JIRA_FIX/.counter")"
assert_eq "lookup names both done blockers" 'key in ("ABC-7","SW2-4")' "$(sent_jql 2)"
assert_eq "wont_do blocker keeps its dependent blocked" "1/1" "$(jq -r '.items[0] | "\(.blocked_by_count)/\(.blocked_by_wont_do_count)"' <<<"$OUT")"
assert_eq "completed blocker resolves its dependent" "0/0" "$(jq -r '.items[1] | "\(.blocked_by_count)/\(.blocked_by_wont_do_count)"' <<<"$OUT")"

printf '500' >"$JIRA_FIX/2.status"
jira_run "$S" --state open
assert_eq "failed lookup → exit 0" "0" "$RC"
assert_eq "failed lookup → both dependents stay blocked, none won't-do" "1/0 1/0" \
  "$(jq -r '[.items[] | "\(.blocked_by_count)/\(.blocked_by_wont_do_count)"] | join(" ")' <<<"$OUT")"
assert_contains "failed lookup → stderr warning" "$ERR" "resolution query failed"
rm -f "$JIRA_FIX/2.body" "$JIRA_FIX/2.status"

jq -cn '{issues: [{key: "SW2-1000", fields: {summary: "Many", status: {statusCategory: {key: "new"}},
  assignee: null, labels: [], issuetype: {name: "Task"}, parent: null,
  issuelinks: [range(1; 102) | {type: {name: "Blocks"},
    inwardIssue: {key: "SW2-\(.)", fields: {status: {statusCategory: {key: "done"}}}}}]}}],
  nextPageToken: null, isLast: true}' >"$JIRA_FIX/1.body"
printf '200' >"$JIRA_FIX/1.status"
jq -cn '{issues: [range(1; 102) | {key: "SW2-\(.)", fields: {resolution: {id: "10000", name: "Done"}}}]}' >"$JIRA_FIX/2.body"
cp "$JIRA_FIX/2.body" "$JIRA_FIX/3.body"
printf '200' >"$JIRA_FIX/2.status"
printf '200' >"$JIRA_FIX/3.status"
jira_run "$S" --state open
assert_eq "101 done blockers → one search plus two lookups" "3" "$(cat "$JIRA_FIX/.counter")"
assert_eq "first lookup carries 100 keys" "100" "$(sent_jql 2 | grep -o '"SW2-' | wc -l | tr -d ' ')"
assert_eq "second lookup carries the 101st key" "1" "$(sent_jql 3 | grep -o '"SW2-' | wc -l | tr -d ' ')"
assert_eq "all completed → resolved" "0/0" "$(jq -r '.items[0] | "\(.blocked_by_count)/\(.blocked_by_wont_do_count)"' <<<"$OUT")"
# A 400 on one chunk (Jira rejects the whole `key in (...)` query for one bad key) fails
# every key in that chunk closed, and only that chunk.
printf '400' >"$JIRA_FIX/3.status"
printf '{"errorMessages":["An issue with key SW2-99 does not exist"]}' >"$JIRA_FIX/3.body"
jira_run "$S" --state open
assert_eq "a 400 on the second chunk → exit 0" "0" "$RC"
assert_eq "a 400 on the second chunk keeps only its key blocking" "1/0" "$(jq -r '.items[0] | "\(.blocked_by_count)/\(.blocked_by_wont_do_count)"' <<<"$OUT")"
rm -f "$JIRA_FIX/2.body" "$JIRA_FIX/2.status" "$JIRA_FIX/3.body" "$JIRA_FIX/3.status"
jira_write_binding '["SW2","ABC"]'

printf '{"issues":[],"nextPageToken":null,"isLast":true}' >"$JIRA_FIX/1.body"
printf '200' >"$JIRA_FIX/1.status"
jira_run "$S" --state all
assert_eq "empty result exit 0" "0" "$RC"
assert_eq "empty result → empty items" "0" "$(jq -r '.items | length' <<<"$OUT")"

printf '401' >"$JIRA_FIX/1.status"
printf '{"errorMessages":["Unauthorized"]}' >"$JIRA_FIX/1.body"
jira_run "$S" --state open
assert_eq "401 on search → auth (4)" "4" "$RC"

printf '200' >"$JIRA_FIX/1.status"
printf '{"errorMessages":["boom"]}' >"$JIRA_FIX/1.body"
jira_run "$S" --state open
assert_eq "2xx without issues array → unavailable (8)" "8" "$RC"

printf '200' >"$JIRA_FIX/1.status"
printf '{"issues":[{"key":"NOT A JIRA KEY","fields":{"summary":"x","status":{"statusCategory":{"key":"new"}},"assignee":null,"labels":[],"issuetype":{"name":"Task"},"parent":null,"issuelinks":[]}}],"nextPageToken":null,"isLast":true}' >"$JIRA_FIX/1.body"
jira_run "$S" --state open
assert_eq "un-normalizable issue in a page → unavailable (8)" "8" "$RC"
assert_eq "and emits no envelope a caller could read as an empty listing" "" "$OUT"

FIX_ROOT="$JIRA_FIX/fixture"
mkdir -p "$FIX_ROOT/adapters"
cp -R "$(dirname "$S")" "$FIX_ROOT/adapters/jira"
cp -R "$(dirname "$S")/../../lib" "$FIX_ROOT/lib"
jq '.limits.list_items_max = 1' "$(dirname "$S")/capabilities.json" >"$FIX_ROOT/adapters/jira/capabilities.json"
printf '200' >"$JIRA_FIX/1.status"
printf '{"issues":[{"key":"SW2-1","fields":{"summary":"First","status":{"statusCategory":{"key":"new"}},"assignee":null,"labels":[],"issuetype":{"name":"Task"},"parent":null,"issuelinks":[]}}],"nextPageToken":"tok-2","isLast":false}' >"$JIRA_FIX/1.body"
jira_run "$FIX_ROOT/adapters/jira/list-items.sh" --state open
assert_eq "a walk stopped at the ceiling → exit 0 (documented truncation)" "0" "$RC"
assert_eq "the ceiling's worth of items" "1" "$(jq '.items | length' <<<"$OUT")"
assert_eq "and the envelope carries truncated:true" "true" "$(jq -c '.truncated' <<<"$OUT")"

[[ $FAILED -eq 0 ]] || exit 1
