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

# --repo naming a well-formed project NOT in project_keys must be refused (exit 2):
# --repo narrows within the declared scope, it cannot widen to an undeclared project.
run_list --repo "test.atlassian.net/OTHER"
assert_eq "out-of-scope --repo project → usage (2)" "2" "$RC"
if [[ ! -e "$FIX/.counter" ]]; then
  pass "out-of-scope --repo made no HTTP call"
else
  fail "out-of-scope --repo made no HTTP call" "no curl call" "curl invoked"
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

# MALFORMED config: project_keys as a scalar string (not an array) passes a naive
# length>0 check but must be rejected as a type error (exit 3) — never assembled into
# `project in ()`. Regression guard for the config-load type check.
jq -cn '{schema_version:"1.0", provider:"jira",
  config:{lease_ttl_hours:24,
    jira:{site:"test.atlassian.net", project_keys:"ABC",
      auth_email:"ci@test.example", auth_env:"JIRA_TEST_TOKEN"}}}' >"$FIX/scalar-binding.json"
WORK_ITEM_TRACKER_BINDING="$FIX/scalar-binding.json" WIT_JIRA_CURL="$FIX/curl" \
  JIRA_TEST_TOKEN="dummy" bash "$S" --state open >/dev/null 2>&1
assert_eq "non-array project_keys → config (3)" "3" "$?"

# rc_for_jira <case-label> <expected-rc> <jira-config-literal> — write a binding whose
# config.jira is the given jq object literal (jq syntax, interpolated into the jq
# program — not --argjson, which would demand strict JSON) and assert list-items
# --state open's exit code. Isolates the config-validation cases below.
rc_for_jira() {
  local label="$1" want="$2" jira="$3"
  rm -f "$FIX/.counter"
  jq -cn "{schema_version:\"1.0\", provider:\"jira\", config:{lease_ttl_hours:24, jira:$jira}}" >"$FIX/cfg-binding.json"
  WORK_ITEM_TRACKER_BINDING="$FIX/cfg-binding.json" WIT_JIRA_CURL="$FIX/curl" \
    JIRA_TEST_TOKEN="dummy" bash "$S" --state open >/dev/null 2>&1
  assert_eq "$label" "$want" "$?"
}

# CREDENTIAL-EGRESS guard: site is the host the token is sent to. A site carrying URL
# structure, or a non-atlassian.net host without the explicit opt-in, is a config error
# (exit 3) BEFORE any request — a tracked binding cannot redirect the credential.
rc_for_jira "site with URL structure → config (3)" "3" \
  '{site:"evil.example/@x.atlassian.net", project_keys:["SW2"], auth_email:"a@b", auth_env:"JIRA_TEST_TOKEN"}'
rc_for_jira "non-atlassian site without opt-in → config (3)" "3" \
  '{site:"attacker.example", project_keys:["SW2"], auth_email:"a@b", auth_env:"JIRA_TEST_TOKEN"}'
# With the explicit custom-domain opt-in, a non-atlassian host is accepted (proceeds to
# the request rather than exit 3) — here a seeded empty page yields a clean exit 0.
printf '{"issues":[],"nextPageToken":null,"isLast":true}' >"$FIX/1.body"
printf '200' >"$FIX/1.status"
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

# blocked_by_link_type, if present, must be a non-empty string: an empty or non-string
# override matches no issuelink → blocked_by_count silently 0 → the frontier surfaces
# actually-blocked tickets. Reject at config load (exit 3).
rc_for_jira "empty blocked_by_link_type → config (3)" "3" \
  '{site:"test.atlassian.net", project_keys:["SW2"], auth_email:"a@b", auth_env:"JIRA_TEST_TOKEN", blocked_by_link_type:""}'
rc_for_jira "non-string blocked_by_link_type → config (3)" "3" \
  '{site:"test.atlassian.net", project_keys:["SW2"], auth_email:"a@b", auth_env:"JIRA_TEST_TOKEN", blocked_by_link_type:[]}'
# A valid non-empty override is accepted (proceeds past config to the request).
printf '{"issues":[],"nextPageToken":null,"isLast":true}' >"$FIX/1.body"
printf '200' >"$FIX/1.status"
rc_for_jira "valid blocked_by_link_type accepted" "0" \
  '{site:"test.atlassian.net", project_keys:["SW2"], auth_email:"a@b", auth_env:"JIRA_TEST_TOKEN", blocked_by_link_type:"Blocked By"}'

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

# A 2xx response lacking an issues array (e.g. an error envelope a proxy returned with
# 200) must fail loudly (exit 8), never collapse to a silent empty frontier.
printf '200' >"$FIX/1.status"
printf '{"errorMessages":["boom"]}' >"$FIX/1.body"
run_list --state open
assert_eq "2xx without issues array → unavailable (8)" "8" "$RC"

[[ $FAILED -eq 0 ]] || exit 1
