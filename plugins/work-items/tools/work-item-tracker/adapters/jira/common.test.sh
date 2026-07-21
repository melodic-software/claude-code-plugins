#!/usr/bin/env bash
# shellcheck disable=SC2154  # FAILED/CASE_NUM initialized by the sourced lib
# common.sh is a sourceable contract lib — assert it sources cleanly and exposes its
# public helpers (no --help contract; it is sourced, never invoked).
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../../tests/lib.sh"
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"

for fn in wit_require_jira_id wit_need_jira_config wit_jira_project_in_scope wit_jira_token \
  wit_jira_http wit_jira_require_ok wit_jira_b64 wit_help_if_requested; do
  if declare -F "$fn" >/dev/null; then
    pass "common.sh exposes $fn"
  else
    fail "common.sh exposes $fn" "declared" "missing"
  fi
done

# Foreign-provider id is well-formed by the shared grammar but must be rejected here.
if wit_require_jira_id "github:o/r#1"; then
  fail "rejects foreign-provider id" "reject" "accepted"
else
  pass "rejects foreign-provider id"
fi
if wit_require_jira_id "jira:acme.atlassian.net/SW2#12"; then
  pass "accepts jira id + sets WIT_ID_* globals"
  assert_eq "id owner is site" "acme.atlassian.net" "$WIT_ID_OWNER"
  assert_eq "id repo is project key" "SW2" "$WIT_ID_REPO"
  assert_eq "id number" "12" "$WIT_ID_NUMBER"
else
  fail "accepts jira id" "accept" "rejected"
fi

# base64 helper is pure — round-trip a known value.
assert_eq "b64 of a:b" "YTpi" "$(wit_jira_b64 'a:b')"

# Project-scope membership is pure over WIT_JIRA_PROJECT_KEYS.
WIT_JIRA_PROJECT_KEYS='["SW2","ABC"]'
if wit_jira_project_in_scope "SW2"; then pass "in-scope project accepted"; else fail "in-scope project accepted" "in" "out"; fi
if wit_jira_project_in_scope "OTHER"; then fail "out-of-scope project rejected" "out" "in"; else pass "out-of-scope project rejected"; fi

# HTTP-status → exit-code mapping is pure; run wit_jira_require_ok in a subshell so
# its exit does not end this suite, and capture the code it exits with.
check_map() {
  local label="$1" status="$2" want="$3"
  (
    WIT_JIRA_STATUS="$status"
    WIT_JIRA_BODY=""
    wit_jira_require_ok "test" 2>/dev/null
  )
  assert_eq "$label" "$want" "$?"
}
check_map "200 → ok (0)" "200" "0"
check_map "401 → auth (4)" "401" "4"
check_map "404 → not-found (5)" "404" "5"
check_map "429 → unavailable (8)" "429" "8"
check_map "503 → unavailable (8)" "503" "8"

[[ $FAILED -eq 0 ]] || exit 1
