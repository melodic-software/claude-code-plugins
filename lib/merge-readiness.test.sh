#!/usr/bin/env bash
# test-scope: plugins/guardrails/hooks/merge-guard-fixtures.sh plugins/guardrails/hooks/guardrails-test-helpers.sh lib/merge-hold-labels.json lib/merge-guard-option.mjs lib/plugin-options.mjs plugins/guardrails/hooks/merge-guard.sh plugins/guardrails/.claude-plugin/plugin.json plugins/source-control/skills/pull-request/scripts/merge-readiness.sh plugins/guardrails/hooks/fixtures/check-runs-ci-status.json plugins/guardrails/hooks/fixtures/reviews-page1.json plugins/guardrails/hooks/fixtures/reviews-page2.json

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
assert_exit "an inherited CLAUDE_PLUGIN_OPTION_ value is not the guardrails setting -> held" 1 "$RC"
ENVS=()

# One merge_guard_ignored_checks setting, both readers. The operator sets it for
# guardrails in their user settings; Claude Code hands the guard hook that value
# as CLAUDE_PLUGIN_OPTION_MERGE_GUARD_IGNORED_CHECKS, and the skill's copy, run
# from a source-control install in the same plugin cache, reads the same entry
# (https://github.com/melodic-software/claude-code-plugins/issues/18822).
CFG="$TEST_TMPDIR/config"
SKILL_COPY="$CFG/plugins/cache/m/source-control/1.0.0/skills/pull-request/scripts"
mkdir -p "$SKILL_COPY"
SC_SCRIPTS="$LIB_DIR/../plugins/source-control/skills/pull-request/scripts"
cp "$SC_SCRIPTS/merge-readiness.sh" "$SC_SCRIPTS/merge-guard-option.mjs" "$SC_SCRIPTS/plugin-options.mjs" \
  "$SC_SCRIPTS/merge-hold-labels.json" "$SKILL_COPY/"
guardrails_setting() {
  jq -n --arg v "$1" '{pluginConfigs: {"guardrails@m": {options: {merge_guard_ignored_checks: $v}}}}' >"$CFG/settings.json"
}
skill_check() {
  OUT=$(env PATH="$BIN:$PATH" FAKE_GH_DIR="$FIX" bash "$SKILL_COPY/merge-readiness.sh" acme/widgets 42 2>&1)
  RC=$?
}
guard_check() {
  run "$1" 'gh pr merge 42' "$2" CLAUDE_PLUGIN_OPTION_MERGE_GUARD_IGNORED_CHECKS="$(jq -r '.pluginConfigs["guardrails@m"].options.merge_guard_ignored_checks' "$CFG/settings.json")"
}
scenario none none green green
jq -n '{total_count: 1, check_runs: [{id: 901, name: "flaky-lint", app: {id: 1, slug: "ci"}, status: "completed", conclusion: "failure"}]}' >"$FIX/checks.json"
guardrails_setting "github-actions:Merge, ci:flaky-lint"
skill_check
assert_exit "custom guardrails setting names the failure -> the skill reads READY" 0 "$RC"
guard_check "custom guardrails setting names the failure -> the guard lets the merge run" 0
guardrails_setting "github-actions:Merge"
skill_check
assert_exit "custom guardrails setting without the failure -> the skill holds" 1 "$RC"
guard_check "custom guardrails setting without the failure -> the guard refuses" 2
rm -f "$CFG/settings.json"
skill_check
assert_exit "no guardrails setting -> the skill applies the default and holds" 1 "$RC"
echo '{"pluginConfigs": []}' >"$CFG/settings.json"
skill_check
assert_exit "an unreadable guardrails setting -> UNCHECKED" 3 "$RC"
assert_contains "unreadable setting -> says which" "$OUT" "merge_guard_ignored_checks setting could not be read"
assert_eq "the built-in default is the guardrails option's declared default" \
  "$(jq -r '.userConfig.merge_guard_ignored_checks.default' "$LIB_DIR/../plugins/guardrails/.claude-plugin/plugin.json")" \
  "$(grep -o 'MERGE_GUARD_IGNORED_CHECKS-[^}]*' "$LIB_DIR/merge-readiness.sh" | cut -d- -f2-)"

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
  jq --arg finished "$1" '.check_runs[0].completed_at = $finished' "$HOOK_DIR/fixtures/check-runs-ci-status.json" >"$FIX/checks.json"
}
pv_judged 2099-01-01T00:00:00Z
check acme/widgets 42
assert_eq "no pr-verify verdict inside the wait -> BLOCKED no-verify-pass" "BLOCKED no-verify-pass" "$(head -n 1 <<<"$OUT")"
pv_judged 2026-01-01T00:00:00Z
check acme/widgets 42
assert_exit "no pr-verify verdict past the wait -> READY" 0 "$RC"
assert_contains "past the wait -> a notice says no verdict was read" "$OUT" "NOTICE: pr-verify has no verdict at abc123"
pv_judged 2026-01-01T00:00:00Z
jq '.check_runs += [.check_runs[0] | .id += 1 | .name = "integration" | .status = "in_progress" | .conclusion = null | .completed_at = null]
  | .total_count = 2 | .check_runs[0].completed_at = "2026-01-01T00:00:00Z"' \
  "$HOOK_DIR/fixtures/check-runs-ci-status.json" >"$FIX/checks.json"
check acme/widgets 42 --auto
assert_eq "no verdict, a check still running, --auto -> the wait has not started, BLOCKED no-verify-pass" \
  "BLOCKED no-verify-pass" "$(head -n 1 <<<"$OUT")"

PAGED="$TEST_TMPDIR/per-page-4"
mkdir -p "$PAGED"
cp "$SC_SCRIPTS/merge-guard-option.mjs" "$SC_SCRIPTS/plugin-options.mjs" "$SC_SCRIPTS/merge-hold-labels.json" "$PAGED/"
sed 's/^MG_PER_PAGE=100$/MG_PER_PAGE=4/' "$CLI" >"$PAGED/merge-readiness.sh"
assert_eq "the 4-per-page copy rewrote the page size" 1 "$(grep -c '^MG_PER_PAGE=4$' "$PAGED/merge-readiness.sh")"
CLI_REAL="$CLI"
CLI="$PAGED/merge-readiness.sh"
CAPTURED="$HOOK_DIR/fixtures"
scenario none none green green
cp "$CAPTURED/reviews-page1.json" "$FIX/reviews.json"
jq '.[-1].state = "CHANGES_REQUESTED"' "$CAPTURED/reviews-page2.json" >"$FIX/reviews_page2.json"
check acme/widgets 42
assert_exit "a change request on the second page of reviews -> held" 1 "$RC"
assert_contains "second page -> names the reviewer" "$OUT" "Changes requested by: kyle-sexton"
rm "$FIX/reviews_page2.json"
check acme/widgets 42
assert_exit "a review list longer than the page cap -> UNCHECKED, which the skill holds on" 3 "$RC"
assert_contains "past the cap -> says why" "$OUT" "more than 80 items at repos/acme/widgets/pulls/42/reviews"
CLI="$CLI_REAL"

echo
# shellcheck disable=SC2154  # PASS and FAIL are the guardrails test helpers' counters
echo "merge-readiness: $PASS passed, $FAIL failed"
((FAIL == 0))
