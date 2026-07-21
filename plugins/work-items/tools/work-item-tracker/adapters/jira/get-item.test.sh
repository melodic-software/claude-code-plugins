#!/usr/bin/env bash
# shellcheck disable=SC2154  # FAILED/CASE_NUM initialized by the sourced helper
# get-item: offline contract tests. The happy path drives the real normalizer with a
# mocked curl (WIT_JIRA_CURL) returning a canned Jira issue — no live Jira call.
set -uo pipefail
S="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/get-item.sh"
source "$(dirname "$S")/../../lib/verb-test-helpers.sh"

# --- offline usage / config errors (no network) ---
assert_help "$S"
assert_usage_error "$S" --nope
assert_usage_error "$S" # no id
assert_usage_error "$S" "not-an-id"
# Foreign-provider id: well-formed grammar, wrong provider → rejected before any I/O.
assert_usage_error "$S" "github:o/r#1"

# --- offline fixture harness: temp binding + mock curl ---
FIX="$(mktemp -d)"
trap 'rm -rf "$FIX"' EXIT

# A mock curl: drains the -K stdin config, returns the Nth seeded "<body>\n<status>"
# by call count (so pagination tests can seed a sequence). Lives in its own dir.
write_mock_curl() {
  local dir="$1"
  cat >"$dir/curl" <<'MOCK'
#!/usr/bin/env bash
cat >/dev/null 2>&1  # drain the -K - config on stdin
d="$(cd "$(dirname "$0")" && pwd)"
n=$(( $(cat "$d/.counter" 2>/dev/null || echo 0) + 1 ))
printf '%s' "$n" >"$d/.counter"
st="$(cat "$d/$n.status" 2>/dev/null || echo 200)"
b="$(cat "$d/$n.body" 2>/dev/null || echo '{}')"
printf '%s\n%s' "$b" "$st"
MOCK
  chmod +x "$dir/curl"
}

write_binding() {
  # write_binding <dir> — a valid jira binding at <dir>/binding.json.
  jq -cn '{schema_version:"1.0", provider:"jira",
    config:{lease_ttl_hours:24,
      jira:{site:"test.atlassian.net", project_keys:["SW2"],
        auth_email:"ci@test.example", auth_env:"JIRA_TEST_TOKEN"}}}' >"$1/binding.json"
}

write_mock_curl "$FIX"
write_binding "$FIX"

# A Jira issue with one OPEN blocker (SW2-9, new) and one CLOSED blocker (SW2-8, done)
# under the standard "Blocks" link type, plus a parent — exercises the OPEN-only
# blocked_by_count and done-exclusion, parent qualification, and state mapping.
cat >"$FIX/1.body" <<'JSON'
{"key":"SW2-12345","fields":{"summary":"Do the thing","status":{"statusCategory":{"key":"indeterminate"}},"assignee":{"accountId":"acc-1"},"labels":["backend","urgent"],"issuetype":{"name":"Task"},"parent":{"key":"SW2-100"},"issuelinks":[{"type":{"name":"Blocks"},"inwardIssue":{"key":"SW2-9","fields":{"status":{"statusCategory":{"key":"new"}}}}},{"type":{"name":"Blocks"},"inwardIssue":{"key":"SW2-8","fields":{"status":{"statusCategory":{"key":"done"}}}}}]}}
JSON
printf '200' >"$FIX/1.status"

run_get() {
  # run_get <id> — invoke get-item under the fixture env; sets OUT and RC.
  rm -f "$FIX/.counter"
  OUT="$(WORK_ITEM_TRACKER_BINDING="$FIX/binding.json" WIT_JIRA_CURL="$FIX/curl" \
    JIRA_TEST_TOKEN="dummy-token" bash "$S" "$@" 2>/dev/null)"
  RC=$?
}

run_get "jira:test.atlassian.net/SW2#12345"
assert_eq "get-item happy path exit 0" "0" "$RC"
assert_eq "schema_version" "1.0" "$(jq -r '.schema_version' <<<"$OUT")"
assert_eq "id qualified" "jira:test.atlassian.net/SW2#12345" "$(jq -r '.id' <<<"$OUT")"
assert_eq "title" "Do the thing" "$(jq -r '.title' <<<"$OUT")"
assert_eq "state open (indeterminate)" "open" "$(jq -r '.state' <<<"$OUT")"
assert_eq "assignee accountId" "acc-1" "$(jq -r '.assignees[0]' <<<"$OUT")"
assert_eq "labels verbatim" "backend,urgent" "$(jq -r '.labels | join(",")' <<<"$OUT")"
assert_eq "type name" "Task" "$(jq -r '.type' <<<"$OUT")"
assert_eq "blocked_by_count OPEN-only" "1" "$(jq -r '.blocked_by_count' <<<"$OUT")"
assert_eq "parent_id qualified" "jira:test.atlassian.net/SW2#100" "$(jq -r '.parent_id' <<<"$OUT")"
assert_eq "url is browse link" "https://test.atlassian.net/browse/SW2-12345" "$(jq -r '.url' <<<"$OUT")"
case "$OUT" in *$'\r'*) fail "stdout CR-free" "no CR" "CR present" ;; *) pass "stdout CR-free" ;; esac

# --- state mapping: a done-category issue normalizes to closed ---
cat >"$FIX/1.body" <<'JSON'
{"key":"SW2-7","fields":{"summary":"Shipped","status":{"statusCategory":{"key":"done"}},"assignee":null,"labels":[],"issuetype":{"name":"Bug"},"parent":null,"issuelinks":[]}}
JSON
printf '200' >"$FIX/1.status"
run_get "jira:test.atlassian.net/SW2#7"
assert_eq "done-category → closed" "closed" "$(jq -r '.state' <<<"$OUT")"
assert_eq "no assignee → empty array" "0" "$(jq -r '.assignees | length' <<<"$OUT")"
assert_eq "no parent → null" "null" "$(jq -r '.parent_id' <<<"$OUT")"

# An assignee object present but with a null accountId (a privacy-restricted user)
# projects to an empty assignees array, not [null] — the frontier keys on emptiness.
cat >"$FIX/1.body" <<'JSON'
{"key":"SW2-6","fields":{"summary":"Restricted","status":{"statusCategory":{"key":"new"}},"assignee":{"accountId":null},"labels":[],"issuetype":{"name":"Task"},"parent":null,"issuelinks":[]}}
JSON
printf '200' >"$FIX/1.status"
run_get "jira:test.atlassian.net/SW2#6"
assert_eq "assignee with null accountId → empty array" "0" "$(jq -r '.assignees | length' <<<"$OUT")"

# --- error paths ---
# Cross-site id (site does not match the bound site) → usage error, before network.
run_get "jira:other.atlassian.net/SW2#1"
assert_eq "cross-site id → usage (2)" "2" "$RC"

# A project key that is grammar-valid in the ID (dots allowed there) but not a real
# Jira key → usage error up front, not an opaque exit 5 from the normalizer's parser.
run_get "jira:test.atlassian.net/SW.2#1"
assert_eq "malformed project key in id → usage (2)" "2" "$RC"
if [[ ! -e "$FIX/.counter" ]]; then
  pass "malformed key made no HTTP call"
else
  fail "malformed key made no HTTP call" "no curl call" "curl invoked"
fi

# A well-formed id for a project NOT in the binding's project_keys (binding declares
# only SW2) must be refused before any fetch — reads are bounded to the declared scope.
run_get "jira:test.atlassian.net/OTHER#1"
assert_eq "out-of-scope project id → usage (2)" "2" "$RC"
if [[ ! -e "$FIX/.counter" ]]; then
  pass "out-of-scope id made no HTTP call"
else
  fail "out-of-scope id made no HTTP call" "no curl call" "curl invoked"
fi

# 404 from Jira → not-found (5).
printf '404' >"$FIX/1.status"
printf '{"errorMessages":["Issue does not exist"]}' >"$FIX/1.body"
run_get "jira:test.atlassian.net/SW2#999"
assert_eq "404 → not-found (5)" "5" "$RC"

# A 2xx response that is not an issue object (no .key) → fail loudly (exit 8), not a
# misleading normalizer crash.
printf '200' >"$FIX/1.status"
printf '{"errorMessages":["boom"]}' >"$FIX/1.body"
run_get "jira:test.atlassian.net/SW2#5"
assert_eq "2xx without issue key → unavailable (8)" "8" "$RC"

# A 2xx issue whose key the normalizer cannot parse → exit 8 with a clear message,
# not a bare/misleading exit from the failed jq.
printf '200' >"$FIX/1.status"
printf '{"key":"NOT A JIRA KEY","fields":{"summary":"x","status":{"statusCategory":{"key":"new"}},"assignee":null,"labels":[],"issuetype":{"name":"Task"},"parent":null,"issuelinks":[]}}' >"$FIX/1.body"
run_get "jira:test.atlassian.net/SW2#5"
assert_eq "un-normalizable issue key → unavailable (8)" "8" "$RC"

# Missing token env var → auth (4), before any curl call.
rm -f "$FIX/.counter"
OUT="$(WORK_ITEM_TRACKER_BINDING="$FIX/binding.json" WIT_JIRA_CURL="$FIX/curl" \
  bash "$S" "jira:test.atlassian.net/SW2#1" 2>/dev/null)"
assert_eq "unset token env → auth (4)" "4" "$?"

# Binding missing required jira config (no project_keys) → config (3).
jq -cn '{schema_version:"1.0", provider:"jira",
  config:{lease_ttl_hours:24, jira:{site:"test.atlassian.net", auth_email:"x@y", auth_env:"JIRA_TEST_TOKEN"}}}' >"$FIX/bad-binding.json"
WORK_ITEM_TRACKER_BINDING="$FIX/bad-binding.json" WIT_JIRA_CURL="$FIX/curl" \
  JIRA_TEST_TOKEN="dummy" bash "$S" "jira:test.atlassian.net/SW2#1" >/dev/null 2>&1
assert_eq "missing project_keys → config (3)" "3" "$?"

[[ $FAILED -eq 0 ]] || exit 1
