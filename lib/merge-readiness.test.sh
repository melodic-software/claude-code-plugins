#!/usr/bin/env bash
# test-scope: plugins/guardrails/hooks/merge-guard-fixtures.sh plugins/guardrails/hooks/guardrails-test-helpers.sh lib/merge-hold-labels.json

# shellcheck disable=SC2016
set -uo pipefail

TEST_TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TEST_TMPDIR"' EXIT
LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../plugins/guardrails/hooks/merge-guard-fixtures.sh source-path=SCRIPTDIR
source "$LIB_DIR/../plugins/guardrails/hooks/merge-guard-fixtures.sh"
CLI="$LIB_DIR/merge-readiness.sh"

check() {
  OUT=$(env PATH="$BIN:$PATH" FAKE_GH_DIR="$FIX" "${ENVS[@]}" bash "$CLI" "$@" 2>&1)
  RC=$?
}
ENVS=()
pr_json() {
  jq -n --argjson labels "${1:-[]}" '{state: "open", head: {sha: "abc123"}, base: {repo: {full_name: "acme/widgets"}},
    labels: ($labels | map({name: .}))}' >"$FIX/pr.json"
}

scenario none none green green
check acme/widgets 42
assert_exit "clean PR -> READY" 0 "$RC"
assert_eq "clean PR -> first line READY" READY "$(head -n 1 <<<"$OUT")"

scenario none none green green
pr_json '["PR-Verify-Failed"]'
check acme/widgets 42
assert_exit "a hold label in another case -> held" 1 "$RC"
assert_eq "hold label -> BLOCKED hold-label" "BLOCKED hold-label" "$(head -n 1 <<<"$OUT")"
assert_contains "hold label -> named as GitHub shows it" "$OUT" "Hold labels: PR-Verify-Failed"

scenario none none green green
pr_json '["Security: Outside-Actor"]'
check acme/widgets 42
assert_eq "outside-actor label in another case -> BLOCKED hold-label" "BLOCKED hold-label" "$(head -n 1 <<<"$OUT")"

scenario none requested green green
check acme/widgets 42
assert_exit "a changes-requested review -> held" 1 "$RC"
assert_contains "changes requested -> names the reviewer" "$OUT" "Changes requested by: bob"

scenario none requested-then-approved green green
check acme/widgets 42
assert_exit "changes requested, then approved -> READY" 0 "$RC"

for conclusion in timed_out cancelled action_required startup_failure stale failure; do
  scenario none none green green
  jq -n --arg c "$conclusion" '{total_count: 1, check_runs: [{id: 901, name: "build", app: {id: 1, slug: "ci"},
    status: "completed", conclusion: $c}]}' >"$FIX/checks.json"
  check acme/widgets 42
  assert_exit "a $conclusion check -> held" 1 "$RC"
  assert_contains "$conclusion -> named as failing" "$OUT" "Failing checks: build"
done

scenario none none green green
jq -n '{total_count: 1, check_runs: [{id: 901, name: "flaky-lint", app: {id: 1, slug: "ci"}, status: "completed", conclusion: "failure"}]}' >"$FIX/checks.json"
check acme/widgets 42
assert_exit "a failure no setting names -> held, never informational" 1 "$RC"
ENVS=(CLAUDE_PLUGIN_OPTION_MERGE_GUARD_IGNORED_CHECKS=ci:flaky-lint)
check acme/widgets 42
assert_exit "the same failure named in merge_guard_ignored_checks -> READY" 0 "$RC"
ENVS=()

scenario none none pending green
check acme/widgets 42
assert_exit "a pending check, immediate merge -> held" 1 "$RC"
check acme/widgets 42 --auto
assert_exit "a pending check, --auto -> READY" 0 "$RC"

scenario unresolved none green green
check acme/widgets 42
assert_eq "an unresolved thread -> BLOCKED not-ready" "BLOCKED not-ready" "$(head -n 1 <<<"$OUT")"
assert_contains "the thread is listed" "$OUT" "src/app.py:12"

scenario unresolved none green green
touch "$FIX/graphql_refused"
check acme/widgets 42
assert_exit "GraphQL refused -> threads read from the cloud route, held" 1 "$RC"
assert_contains "cloud route -> the thread is listed" "$OUT" "src/app.py:12"

scenario none none green green
touch "$FIX/graphql_refused"
check acme/widgets 42
assert_exit "GraphQL refused, cloud route clean -> READY" 0 "$RC"

scenario none none green green
touch "$FIX/fail"
check acme/widgets 42
assert_exit "an unreadable PR -> UNCHECKED, which the skill holds on" 3 "$RC"
assert_contains "unreadable -> says so" "$OUT" "UNCHECKED:"

scenario none none green green
check acme/widgets 42 --head 0123456789abcdef0123456789abcdef01234567
assert_eq "a moved head -> BLOCKED head-moved" "BLOCKED head-moved" "$(head -n 1 <<<"$OUT")"

scenario none none green green
echo '{"state":"closed","head":{"sha":"abc123"},"base":{"repo":{"full_name":"acme/widgets"}}}' >"$FIX/pr.json"
check acme/widgets 42
assert_eq "a closed PR -> BLOCKED closed" "BLOCKED closed" "$(head -n 1 <<<"$OUT")"

check 'acme/widgets;x' 42
assert_exit "a repository that is not owner/repo -> usage" 2 "$RC"
check acme/widgets 42 --head HEAD
assert_exit "a head that is not a full sha -> usage" 2 "$RC"

pv_judged() {
  scenario none none green green
  echo '{"state":"open","head":{"sha":"abc123","ref":"feat/x","repo":{"full_name":"acme/widgets"}},"base":{"ref":"main","repo":{"full_name":"acme/widgets","default_branch":"main"}},"user":{"id":9,"login":"kyle","type":"User"},"labels":[]}' >"$FIX/pr.json"
  printf '{"data":{"repository":{"w":{"oid":"f00"},"c":{"text":"merge:\\n  verify-authors: any\\n"},"t":{"text":""}}}}\n' >"$FIX/graphql_scope.json"
  jq -n --arg finished "$1" '{total_count: 1, check_runs: [{id: 901, name: "CI Status", app: {id: 1, slug: "github-actions"},
    status: "completed", conclusion: "success", completed_at: $finished}]}' >"$FIX/checks.json"
}
pv_judged 2099-01-01T00:00:00Z
check acme/widgets 42
assert_eq "no pr-verify verdict inside the wait -> BLOCKED no-verify-pass" "BLOCKED no-verify-pass" "$(head -n 1 <<<"$OUT")"
pv_judged 2026-01-01T00:00:00Z
check acme/widgets 42
assert_exit "no pr-verify verdict past the wait -> READY" 0 "$RC"
assert_contains "past the wait -> a notice says no verdict was read" "$OUT" "NOTICE: pr-verify has no verdict at abc123"

echo
# shellcheck disable=SC2154  # PASS and FAIL are the guardrails test helpers' counters
echo "merge-readiness: $PASS passed, $FAIL failed"
((FAIL == 0))
