#!/usr/bin/env bash
# Contract test for block-foreground-wait.sh (guardrails plugin).
#
# Black-box: each case pipes a PreToolUse payload into the guard, alone and
# under run-guards.sh, and asserts the same exit code both ways (2 = denied,
# 0 = allowed).

# shellcheck disable=SC2016  # command strings are literal test input, never expanded here
# test-scope: plugins/guardrails/hooks/hooks.json plugins/guardrails/.claude-plugin/plugin.json
set -uo pipefail

HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GUARD_UNDER_TEST="$HOOK_DIR/block-foreground-wait.sh"
TEST_TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TEST_TMPDIR"' EXIT

# shellcheck source=guardrails-test-helpers.sh
source "$HOOK_DIR/guardrails-test-helpers.sh"
jq_crlf_free
unset CLAUDE_PLUGIN_OPTION_BLOCK_FOREGROUND_WAIT_ENABLED

REASON_UNTIL='BLOCKED: This `until` loop waits in the foreground. Run the command with run_in_background set to true, or watch it with the Monitor tool'
REASON_WATCH='BLOCKED: This `--watch` command waits in the foreground. Run it with run_in_background set to true, or watch it with the Monitor tool'
NL=$'\n'

# payload <command> <run_in_background JSON value>
payload() {
  jq -cn --arg c "$1" --argjson b "$2" '{tool_name:"Bash",tool_input:{command:$c,run_in_background:$b}}'
}

# deny_with <reason> <label> <command> [guard_invoke option ...]
deny_with() {
  local reason="$1" label="$2" command="$3" via
  shift 3
  for via in direct dispatched; do
    guard_invoke --via "$via" --command "$command" "$@"
    assert_exit "$label ($via)" 2 "$GUARD_RC"
    assert_contains "$label ($via): reason" "$GUARD_ERR" "$reason"
  done
}
deny_until() { deny_with "$REASON_UNTIL" "$@"; }
deny_watch() { deny_with "$REASON_WATCH" "$@"; }

# allow <label> <command> [guard_invoke option ...]
allow() {
  local label="$1" command="$2"
  shift 2
  expect_both "$label" 0 --command "$command" "$@"
}

# --- denied -------------------------------------------------------------------
deny_until "until loop" 'until gh run view 1 --json status | grep -q completed; do sleep 10; done'
deny_until "until after a separator" 'echo start; until test -f done.flag; do sleep 5; done'
deny_until "until after &&" 'cd /srv && until curl -sf localhost:8080; do sleep 1; done'
deny_until "until on a later line" "echo start${NL}until test -f x; do sleep 1; done"
deny_until "until inside a do body" 'while true; do until test -f x; do sleep 1; done; break; done'
deny_until "until in a subshell" '(until test -f x; do sleep 1; done)'
deny_until "until as an if condition" 'if until test -f x; do sleep 1; done; then echo ok; fi'
deny_until "until with a tab" $'until\ttest -f x; do sleep 1; done'
deny_until "run_in_background false" '' --payload "$(payload 'until test -f x; do sleep 1; done' false)"
deny_watch "gh pr checks --watch" 'gh pr checks 42 --watch'
deny_watch "gh run watch flag after options" 'gh run view 99 --exit-status --watch'
deny_watch "--watch with an env prefix" 'NODE_ENV=test npx jest --watch'
deny_watch "--watch after a pipe" 'cat list | xargs kubectl get pods --watch'
deny_watch "--watch in a later segment" 'git push && gh pr checks --watch'

# --- allowed ------------------------------------------------------------------
BG_UNTIL=$(payload 'until test -f x; do sleep 1; done' true)
BG_WATCH=$(payload 'gh pr checks 42 --watch' true)
expect_both "until in the background" 0 --payload "$BG_UNTIL"
expect_both "--watch in the background" 0 --payload "$BG_WATCH"
allow "until as an argument" 'git log --grep until'
allow "until in double quotes" 'git commit -m "fix: wait; until ready"'
allow "until in single quotes" "echo 'retry; until it works'"
allow "until in ANSI-C quotes with an escaped quote" "echo \$'it\\'s; until x'"
allow "until in a comment" "ls # loop; until done"
allow "until in a heredoc body" "cat > notes.md <<'EOF'${NL}until the fix lands${NL}EOF"
allow "a word that starts with until is not until" 'until_ready x; do y; done'
allow "--watch in quotes" 'gh issue create --title "add --watch support"'
allow "--watch after --" 'grep -- --watch README.md'
allow "--watch printed by echo" 'echo --watch'
allow "--watch-path is another flag" 'deno run --watch-path=src main.ts'
allow "--watch=false" 'jest --watch=false'
allow "watch command" 'watch -n 5 ls'
allow "plain command" 'gh pr checks 42'
allow "PowerShell tool" 'until x; do y; done' --tool PowerShell

# --- kill switch --------------------------------------------------------------
expect_both "kill switch off: allowed" 0 --command 'gh pr checks 42 --watch' \
  -- CLAUDE_PLUGIN_OPTION_BLOCK_FOREGROUND_WAIT_ENABLED=false

# --- registration -------------------------------------------------------------
row=$(jq -r '.hooks.PreToolUse[] | select(.matcher == "Bash|PowerShell") | .hooks[].args | map(tostring) | join(" ")' "$HOOK_DIR/hooks.json")
assert_contains "hooks.json runs the guard on the Bash|PowerShell row" "$row" " block-foreground-wait.sh"
assert_eq "plugin.json declares the kill switch, default on" "true" \
  "$(jq -r '.userConfig.block_foreground_wait_enabled.default' "$HOOK_DIR/../.claude-plugin/plugin.json")"

report
