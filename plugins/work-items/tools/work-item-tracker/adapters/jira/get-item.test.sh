#!/usr/bin/env bash
# shellcheck disable=SC2154  # FAILED/CASE_NUM initialized by the sourced helper
# get-item: offline contract tests. The happy path drives the real normalizer with a
# mocked curl (WIT_JIRA_CURL) returning a canned Jira issue — no live Jira call.
set -uo pipefail
S="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/get-item.sh"
source "$(dirname "$S")/../../lib/verb-test-helpers.sh"
# shellcheck source=mock.sh
source "$(dirname "$S")/mock.sh"

# --- offline usage / config errors (no network) ---
assert_help "$S"
assert_usage_error "$S" --nope
assert_usage_error "$S" # no id
assert_usage_error "$S" "not-an-id"
# Foreign-provider id: well-formed grammar, wrong provider → rejected before any I/O.
assert_usage_error "$S" "github:o/r#1"

# --- offline fixture harness: temp binding + mock curl ---
jira_fixture_init
trap 'rm -rf "$JIRA_FIX"' EXIT
jira_write_binding '["SW2"]'

# A Jira issue with one OPEN blocker (SW2-9, new) and one CLOSED blocker (SW2-8, done)
# under the standard "Blocks" link type, plus a parent — exercises the OPEN-only
# blocked_by_count and done-exclusion, parent qualification, and state mapping.
cat >"$JIRA_FIX/1.body" <<'JSON'
{"key":"SW2-12345","fields":{"summary":"Do the thing","status":{"statusCategory":{"key":"indeterminate"}},"assignee":{"accountId":"acc-1"},"labels":["backend","urgent"],"issuetype":{"name":"Task"},"parent":{"key":"SW2-100"},"issuelinks":[{"type":{"name":"Blocks"},"inwardIssue":{"key":"SW2-9","fields":{"status":{"statusCategory":{"key":"new"}}}}},{"type":{"name":"Blocks"},"inwardIssue":{"key":"SW2-8","fields":{"status":{"statusCategory":{"key":"done"}}}}}]}}
JSON
printf '200' >"$JIRA_FIX/1.status"
# Call 2 is the resolution lookup for the done blocker SW2-8: resolved as Done.
printf '{"issues":[{"key":"SW2-8","fields":{"resolution":{"name":"Done"}}}]}' >"$JIRA_FIX/2.body"
printf '200' >"$JIRA_FIX/2.status"

jira_run "$S" "jira:test.atlassian.net/SW2#12345"
assert_eq "get-item happy path exit 0" "0" "$RC"
assert_eq "schema_version" "1.0" "$(jq -r '.schema_version' <<<"$OUT")"
assert_eq "id qualified" "jira:test.atlassian.net/SW2#12345" "$(jq -r '.id' <<<"$OUT")"
assert_eq "title" "Do the thing" "$(jq -r '.title' <<<"$OUT")"
assert_eq "state open (indeterminate)" "open" "$(jq -r '.state' <<<"$OUT")"
assert_eq "assignee accountId" "acc-1" "$(jq -r '.assignees[0]' <<<"$OUT")"
assert_eq "labels verbatim" "backend,urgent" "$(jq -r '.labels | join(",")' <<<"$OUT")"
assert_eq "type name" "Task" "$(jq -r '.type' <<<"$OUT")"
assert_eq "blocked_by_count: a Done-resolved blocker is resolved" "1" "$(jq -r '.blocked_by_count' <<<"$OUT")"
assert_eq "blocked_by_wont_do_count 0 for a Done resolution" "0" "$(jq -r '.blocked_by_wont_do_count' <<<"$OUT")"
assert_eq "parent_id qualified" "jira:test.atlassian.net/SW2#100" "$(jq -r '.parent_id' <<<"$OUT")"
assert_eq "url is browse link" "https://test.atlassian.net/browse/SW2-12345" "$(jq -r '.url' <<<"$OUT")"
case "$OUT" in *$'\r'*) fail "stdout CR-free" "no CR" "CR present" ;; *) pass "stdout CR-free" ;; esac
lookup="$(awk '/^--data$/{getline; print; exit}' "$JIRA_FIX/2.args")"
assert_eq "resolution lookup JQL names only the done blocker" 'key in ("SW2-8")' "$(jq -r '.jql' <<<"$lookup")"
assert_eq "resolution lookup asks for the resolution field" '["resolution"]' "$(jq -c '.fields' <<<"$lookup")"

# --- won't-do: a done blocker whose resolution is in wont_do_resolutions ---
# with_lookup <resolution-lookup-body> <status> — run the happy-path issue with
# call 2 answered by the given body and status; sets OUT.
with_lookup() {
  printf '%s' "$1" >"$JIRA_FIX/2.body"
  printf '%s' "$2" >"$JIRA_FIX/2.status"
  jira_run "$S" "jira:test.atlassian.net/SW2#12345"
}
with_lookup '{"issues":[{"key":"SW2-8","fields":{"resolution":{"name":"Won\u0027t Do"}}}]}' 200
assert_eq "Won't Do blocker keeps blocking" "2" "$(jq -r '.blocked_by_count' <<<"$OUT")"
assert_eq "Won't Do blocker is counted as won't-do" "1" "$(jq -r '.blocked_by_wont_do_count' <<<"$OUT")"
with_lookup '{"issues":[{"key":"SW2-8","fields":{"resolution":{"name":"duplicate"}}}]}' 200
assert_eq "Duplicate matches case-insensitively" "1" "$(jq -r '.blocked_by_wont_do_count' <<<"$OUT")"
with_lookup '{"issues":[{"key":"SW2-8","fields":{"resolution":null}}]}' 200
assert_eq "a done blocker with no resolution is resolved" "1" "$(jq -r '.blocked_by_count' <<<"$OUT")"

# A failed lookup, or one that does not return the blocker, fails closed: the done
# blocker keeps blocking without counting as won't-do, and the item still emits.
with_lookup '{"errorMessages":["boom"]}' 500
assert_eq "failed lookup still exits 0" "0" "$RC"
assert_eq "failed lookup keeps the done blocker blocking" "2" "$(jq -r '.blocked_by_count' <<<"$OUT")"
assert_eq "failed lookup counts no won't-do" "0" "$(jq -r '.blocked_by_wont_do_count' <<<"$OUT")"
with_lookup '{"issues":[]}' 200
assert_eq "a blocker the lookup did not return keeps blocking" "2" "$(jq -r '.blocked_by_count' <<<"$OUT")"

# A binding override names the instance's own resolutions; an empty list turns the
# lookup off, so the done blocker is resolved with no second request.
jira_write_binding '["SW2"]' '{"wont_do_resolutions":["Abandoned"]}'
with_lookup '{"issues":[{"key":"SW2-8","fields":{"resolution":{"name":"Abandoned"}}}]}' 200
assert_eq "an overridden resolution name counts as won't-do" "1" "$(jq -r '.blocked_by_wont_do_count' <<<"$OUT")"
with_lookup '{"issues":[{"key":"SW2-8","fields":{"resolution":{"name":"Won\u0027t Do"}}}]}' 200
assert_eq "the override replaces the default list" "0" "$(jq -r '.blocked_by_wont_do_count' <<<"$OUT")"
jira_write_binding '["SW2"]' '{"wont_do_resolutions":[]}'
jira_run "$S" "jira:test.atlassian.net/SW2#12345"
assert_eq "empty wont_do_resolutions makes one request" "1" "$(cat "$JIRA_FIX/.counter")"
assert_eq "empty wont_do_resolutions leaves the done blocker resolved" "1" "$(jq -r '.blocked_by_count' <<<"$OUT")"
jira_write_binding '["SW2"]' '{"wont_do_resolutions":"Won\u0027t Do"}'
jira_run "$S" "jira:test.atlassian.net/SW2#12345"
assert_eq "non-array wont_do_resolutions → config (3)" "3" "$RC"
jira_write_binding '["SW2"]' '{"wont_do_resolutions":[""]}'
jira_run "$S" "jira:test.atlassian.net/SW2#12345"
assert_eq "empty-string wont_do_resolutions element → config (3)" "3" "$RC"

# A done blocker outside project_keys is never looked up (the declared read scope) and
# stays resolved.
jira_write_binding '["SW2"]'
cat >"$JIRA_FIX/1.body" <<'JSON'
{"key":"SW2-12346","fields":{"summary":"Cross-project","status":{"statusCategory":{"key":"new"}},"assignee":null,"labels":[],"issuetype":{"name":"Task"},"parent":null,"issuelinks":[{"type":{"name":"Blocks"},"inwardIssue":{"key":"OTHER-3","fields":{"status":{"statusCategory":{"key":"done"}}}}}]}}
JSON
jira_run "$S" "jira:test.atlassian.net/SW2#12346"
assert_eq "out-of-scope done blocker makes no lookup" "1" "$(cat "$JIRA_FIX/.counter")"
assert_eq "out-of-scope done blocker is resolved" "0" "$(jq -r '.blocked_by_count' <<<"$OUT")"
rm -f "$JIRA_FIX/2.body" "$JIRA_FIX/2.status"

# --- state mapping: a done-category issue normalizes to closed ---
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

# --- error paths ---
# Cross-site id (site does not match the bound site) → usage error, before network.
jira_run "$S" "jira:other.atlassian.net/SW2#1"
assert_eq "cross-site id → usage (2)" "2" "$RC"

# A project key that is grammar-valid in the ID (dots allowed there) but not a real
# Jira key → usage error up front, not an opaque exit 5 from the normalizer's parser.
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

# 404 from Jira → not-found (5).
printf '404' >"$JIRA_FIX/1.status"
printf '{"errorMessages":["Issue does not exist"]}' >"$JIRA_FIX/1.body"
jira_run "$S" "jira:test.atlassian.net/SW2#999"
assert_eq "404 → not-found (5)" "5" "$RC"

# A 2xx response that is not an issue object (no .key) → fail loudly (exit 8), not a
# misleading normalizer crash.
printf '200' >"$JIRA_FIX/1.status"
printf '{"errorMessages":["boom"]}' >"$JIRA_FIX/1.body"
jira_run "$S" "jira:test.atlassian.net/SW2#5"
assert_eq "2xx without issue key → unavailable (8)" "8" "$RC"

# A 2xx issue whose key the normalizer cannot parse → exit 8 with a clear message,
# not a bare/misleading exit from the failed jq.
printf '200' >"$JIRA_FIX/1.status"
printf '{"key":"NOT A JIRA KEY","fields":{"summary":"x","status":{"statusCategory":{"key":"new"}},"assignee":null,"labels":[],"issuetype":{"name":"Task"},"parent":null,"issuelinks":[]}}' >"$JIRA_FIX/1.body"
jira_run "$S" "jira:test.atlassian.net/SW2#5"
assert_eq "un-normalizable issue key → unavailable (8)" "8" "$RC"

# Missing token env var → auth (4), before any curl call.
WORK_ITEM_TRACKER_BINDING="$JIRA_FIX/binding.json" WIT_JIRA_CURL="$JIRA_FIX/curl" \
  bash "$S" "jira:test.atlassian.net/SW2#1" >/dev/null 2>&1
assert_eq "unset token env → auth (4)" "4" "$?"

# Binding missing required jira config (no project_keys) → config (3).
jq -cn '{schema_version:"1.0", provider:"jira",
  config:{lease_ttl_hours:24, jira:{site:"test.atlassian.net", auth_email:"x@y", auth_env:"JIRA_TEST_TOKEN"}}}' >"$JIRA_FIX/bad-binding.json"
WORK_ITEM_TRACKER_BINDING="$JIRA_FIX/bad-binding.json" WIT_JIRA_CURL="$JIRA_FIX/curl" \
  JIRA_TEST_TOKEN="dummy" bash "$S" "jira:test.atlassian.net/SW2#1" >/dev/null 2>&1
assert_eq "missing project_keys → config (3)" "3" "$?"

[[ $FAILED -eq 0 ]] || exit 1
