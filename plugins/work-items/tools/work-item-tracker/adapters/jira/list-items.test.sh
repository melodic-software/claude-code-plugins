#!/usr/bin/env bash
# shellcheck disable=SC2154  # FAILED/CASE_NUM initialized by the sourced helper
# list-items: offline contract tests. The happy path drives the real normalizer +
# nextPageToken pagination with a mocked curl (WIT_JIRA_CURL) returning canned
# /search/jql pages — no live Jira call.
set -uo pipefail
S="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/list-items.sh"
source "$(dirname "$S")/../../lib/verb-test-helpers.sh"

# --- offline usage errors (no network) ---
assert_help "$S"
assert_usage_error "$S" --state bogus
assert_usage_error "$S" --unknown-flag

# --- offline fixture harness: temp binding + mock curl (call-count sequenced) ---
FIX="$(mktemp -d)"
trap 'rm -rf "$FIX"' EXIT

cat >"$FIX/curl" <<'MOCK'
#!/usr/bin/env bash
cat >/dev/null 2>&1  # drain the -K - config on stdin
d="$(cd "$(dirname "$0")" && pwd)"
n=$(( $(cat "$d/.counter" 2>/dev/null || echo 0) + 1 ))
printf '%s' "$n" >"$d/.counter"
printf '%s\n' "$@" >"$d/$n.args"  # record argv so tests can assert the --data JQL
st="$(cat "$d/$n.status" 2>/dev/null || echo 200)"
b="$(cat "$d/$n.body" 2>/dev/null || echo '{}')"
printf '%s\n%s' "$b" "$st"
MOCK
chmod +x "$FIX/curl"

# sent_jql <call-n> — extract the .jql field of the JSON body the adapter POSTed on
# the Nth mock-curl call (the value of the --data argument it recorded).
sent_jql() {
  local data
  data="$(awk '/^--data$/{getline; print; exit}' "$FIX/$1.args")"
  jq -r '.jql' <<<"$data"
}

jq -cn '{schema_version:"1.0", provider:"jira",
  config:{lease_ttl_hours:24,
    jira:{site:"test.atlassian.net", project_keys:["SW2","ABC"],
      auth_email:"ci@test.example", auth_env:"JIRA_TEST_TOKEN"}}}' >"$FIX/binding.json"

# Two pages: page 1 carries a continuation token + isLast false, page 2 closes it.
cat >"$FIX/1.body" <<'JSON'
{"issues":[{"key":"SW2-1","fields":{"summary":"First","status":{"statusCategory":{"key":"new"}},"assignee":null,"labels":["a"],"issuetype":{"name":"Task"},"parent":null,"issuelinks":[]}}],"nextPageToken":"tok-2","isLast":false}
JSON
printf '200' >"$FIX/1.status"
cat >"$FIX/2.body" <<'JSON'
{"issues":[{"key":"ABC-42","fields":{"summary":"Second","status":{"statusCategory":{"key":"indeterminate"}},"assignee":{"accountId":"acc-9"},"labels":[],"issuetype":{"name":"Story"},"parent":{"key":"ABC-1"},"issuelinks":[{"type":{"name":"Blocks"},"inwardIssue":{"key":"ABC-5","fields":{"status":{"statusCategory":{"key":"new"}}}}}]}}],"nextPageToken":null,"isLast":true}
JSON
printf '200' >"$FIX/2.status"

run_list() {
  rm -f "$FIX/.counter"
  OUT="$(WORK_ITEM_TRACKER_BINDING="$FIX/binding.json" WIT_JIRA_CURL="$FIX/curl" \
    JIRA_TEST_TOKEN="dummy-token" bash "$S" "$@" 2>/dev/null)"
  RC=$?
}

run_list --state open
assert_eq "list-items exit 0" "0" "$RC"
assert_eq "schema_version" "1.0" "$(jq -r '.schema_version' <<<"$OUT")"
assert_eq "paginated across 2 pages → 2 items" "2" "$(jq -r '.items | length' <<<"$OUT")"
assert_eq "mock curl called twice" "2" "$(cat "$FIX/.counter")"
assert_eq "page-1 item id" "jira:test.atlassian.net/SW2#1" "$(jq -r '.items[0].id' <<<"$OUT")"
assert_eq "page-2 item id" "jira:test.atlassian.net/ABC#42" "$(jq -r '.items[1].id' <<<"$OUT")"
assert_eq "page-2 item blocked_by_count" "1" "$(jq -r '.items[1].blocked_by_count' <<<"$OUT")"
assert_eq "page-2 item parent qualified" "jira:test.atlassian.net/ABC#1" "$(jq -r '.items[1].parent_id' <<<"$OUT")"
case "$OUT" in *$'\r'*) fail "stdout CR-free" "no CR" "CR present" ;; *) pass "stdout CR-free" ;; esac

# The literal JQL sent on page 1 scopes to the configured project_keys and excludes
# done categories, with each key wrapped in its own quoted literal — asserting the
# actual --data payload, not just that curl was called.
assert_eq "open-state JQL scopes projects + excludes done" \
  'project in ("SW2","ABC") AND statusCategory not in ("done","completed") ORDER BY created ASC' \
  "$(sent_jql 1)"

# --repo narrows to one project.
rm -f "$FIX/2.body" "$FIX/2.status"
printf '{"issues":[],"nextPageToken":null,"isLast":true}' >"$FIX/1.body"
printf '200' >"$FIX/1.status"
run_list --repo "test.atlassian.net/ABC" --state all
assert_eq "--repo scopes to one project" 'project in ("ABC") ORDER BY created ASC' "$(sent_jql 1)"

# --repo narrows to one project; a site mismatch is a usage error (before network).
run_list --repo "wrong.atlassian.net/SW2"
assert_eq "cross-site --repo → usage (2)" "2" "$RC"

# HOSTILE --repo project key with an embedded quote must be rejected before any JQL is
# built (exit 2), never break out of the `project in (...)` literal (JQL injection).
# run_list clears .counter first; a rejection before any HTTP call leaves it absent.
run_list --repo 'test.atlassian.net/SW2") OR (1=1) OR ("x'
assert_eq "injection --repo key → usage (2)" "2" "$RC"
if [[ ! -e "$FIX/.counter" ]]; then
  pass "injection --repo made no HTTP call"
else
  fail "injection --repo made no HTTP call" "no curl call" "curl invoked"
fi

# HOSTILE config: a configured project key with an embedded quote is a config error
# (exit 3), caught at config load before any query is assembled.
jq -cn '{schema_version:"1.0", provider:"jira",
  config:{lease_ttl_hours:24,
    jira:{site:"test.atlassian.net", project_keys:["SW2\") OR (1=1) OR (\"x"],
      auth_email:"ci@test.example", auth_env:"JIRA_TEST_TOKEN"}}}' >"$FIX/evil-binding.json"
WORK_ITEM_TRACKER_BINDING="$FIX/evil-binding.json" WIT_JIRA_CURL="$FIX/curl" \
  JIRA_TEST_TOKEN="dummy" bash "$S" --state open >/dev/null 2>&1
assert_eq "injection project_keys config → config (3)" "3" "$?"

# A single empty page (no token) terminates cleanly with an empty envelope.
rm -f "$FIX/1.body" "$FIX/2.body" "$FIX/1.status" "$FIX/2.status" "$FIX/.counter"
printf '{"issues":[],"nextPageToken":null,"isLast":true}' >"$FIX/1.body"
printf '200' >"$FIX/1.status"
run_list --state all
assert_eq "empty result exit 0" "0" "$RC"
assert_eq "empty result → empty items" "0" "$(jq -r '.items | length' <<<"$OUT")"

# Auth failure surfaces from the search call as exit 4.
printf '401' >"$FIX/1.status"
printf '{"errorMessages":["Unauthorized"]}' >"$FIX/1.body"
run_list --state open
assert_eq "401 on search → auth (4)" "4" "$RC"

[[ $FAILED -eq 0 ]] || exit 1
