#!/usr/bin/env bash

# shellcheck disable=SC2016  # command strings are literal test input, never expanded here
# test-scope: plugins/guardrails/hooks/hooks.json plugins/guardrails/.claude-plugin/plugin.json
set -uo pipefail

HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GUARD_UNDER_TEST="$HOOK_DIR/block-pr-poller.sh"
TEST_TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TEST_TMPDIR"' EXIT

# shellcheck source=guardrails-test-helpers.sh
source "$HOOK_DIR/guardrails-test-helpers.sh"
jq_crlf_free
unset CLAUDE_PLUGIN_OPTION_BLOCK_PR_POLLER_ENABLED

REASON='BLOCKED: This loop polls a pull request and sleeps between reads, which spends the GitHub API budget. Watch a pull request with /source-control:pull-request monitor'
NL=$'\n'

bg() {
  jq -cn --arg c "$1" '{tool_name:"Bash",tool_input:{command:$c,run_in_background:true}}'
}

deny() {
  local label="$1" via
  shift
  for via in direct dispatched; do
    guard_invoke --via "$via" "$@"
    assert_exit "$label ($via)" 2 "$GUARD_RC"
    assert_contains "$label ($via): reason" "$GUARD_ERR" "$REASON"
  done
}
deny_monitor() { deny "$1 (Monitor)" --tool Monitor --command "$2"; }
deny_bg() { deny "$1 (background Bash)" --payload "$(bg "$2")"; }

allow_monitor() { expect_both "$1 (Monitor)" 0 --tool Monitor --command "$2"; }
allow_bg() { expect_both "$1 (background Bash)" 0 --payload "$(bg "$2")"; }

ARTIFACTS='while true; do gh api -X GET repos/o/r/actions/artifacts --jq ".artifacts[0].name"; gh pr view 7 -R o/r --json state,mergeStateStatus; sleep 90; done'
KILL_LOOP='while kill -0 "$pid" 2>/dev/null; do gh pr view 7 -R o/r --json statusCheckRollup; sleep 15; done'
CHECKS='while true; do gh pr checks 7 -R o/r; sleep 60; done'
UNTIL='until gh pr view 7 --json state --jq .state | grep -q MERGED; do sleep 30; done'

deny_monitor "artifacts and pr view poll" "$ARTIFACTS"
deny_bg "artifacts and pr view poll" "$ARTIFACTS"
deny_monitor "kill -0 loop around gh pr view" "$KILL_LOOP"
deny_bg "kill -0 loop around gh pr view" "$KILL_LOOP"
deny_monitor "gh pr checks loop" "$CHECKS"
deny_bg "gh pr checks loop" "$CHECKS"
deny_monitor "until loop" "$UNTIL"
deny_bg "until loop" "$UNTIL"
deny_monitor "gh pr status loop on a later line" "echo start${NL}while :; do${NL}  gh pr status${NL}  sleep 45${NL}done"
deny_monitor "check-runs poll" 'while true; do gh api repos/o/r/commits/abc123/check-runs; sleep 30; done'
deny_monitor "combined status poll" 'while true; do gh api "repos/o/r/commits/main/status"; sleep 30; done'
deny_monitor "issue comments poll" 'while true; do gh api "repos/o/r/issues/7/comments?since=$last"; sleep 30; done'
deny_monitor "pulls poll" 'while true; do gh api repos/o/r/pulls/7/reviews; sleep 30; done'
deny_monitor "for over a seq range" 'for i in $(seq 1 60); do gh pr checks 7; sleep 30; done'
deny_monitor "for over a brace range" 'for i in {1..60}; do gh pr checks 7; sleep 30; done'
deny_monitor "C-style for" 'for ((i = 0; i < 60; i++)); do gh pr view 7; sleep 30; done'
deny_monitor "loop inside bash -c" "bash -c 'while true; do gh pr checks 7; sleep 60; done'"

allow_monitor "the monitor skill's poll script" 'bash "/plugins/source-control/skills/pull-request/scripts/monitor-poll.sh" --pr 7 --checkout "/repo"'
allow_bg "the monitor skill's poll script" 'bash "/plugins/source-control/skills/pull-request/scripts/monitor-poll.sh" --pr 7 --repo o/r --interval 60'
allow_monitor "gh event listen" 'gh event listen --resource https://github.com/o/r/pull/7 --follow --event com.github.pull_request.review.submitted.v1'
allow_monitor "event loop with no sleep" 'while gh event listen --resource https://github.com/o/r/pull/7; do gh pr checks 7; done'
allow_monitor "loop with no gh call" 'while true; do tail -n 1 build.log; sleep 5; done'
allow_bg "loop with no gh call" 'until test -f done.flag; do sleep 1; done'
allow_monitor "loop over an unrelated gh read" 'while true; do gh run list -L 1; sleep 60; done'
allow_monitor "loop over an unrelated gh api path" 'while true; do gh api rate_limit; sleep 60; done'
allow_bg "single non-looping gh call" 'sleep 30; gh pr checks 7'
allow_bg "for over a literal list" 'for pr in 7 8 9; do gh pr view "$pr"; sleep 1; done'
expect_both "foreground Bash" 0 --command "$CHECKS"
expect_both "PowerShell tool" 0 --tool PowerShell --command "$CHECKS"

expect_both "kill switch off: allowed" 0 --tool Monitor --command "$CHECKS" \
  -- CLAUDE_PLUGIN_OPTION_BLOCK_PR_POLLER_ENABLED=false

for matcher in 'Bash|PowerShell' 'Monitor'; do
  row=$(jq -r --arg m "$matcher" '.hooks.PreToolUse[] | select(.matcher == $m) | .hooks[].args | map(tostring) | join(" ")' "$HOOK_DIR/hooks.json")
  assert_contains "hooks.json runs the guard on the $matcher row" "$row" " block-pr-poller.sh"
done
assert_eq "plugin.json declares the kill switch, default on" "true" \
  "$(jq -r '.userConfig.block_pr_poller_enabled.default' "$HOOK_DIR/../.claude-plugin/plugin.json")"

report
