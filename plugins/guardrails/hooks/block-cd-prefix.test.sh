#!/usr/bin/env bash
# Contract test for block-cd-prefix.sh (guardrails plugin).
#
# Black-box: each case pipes a PreToolUse payload into the guard, alone and
# under run-guards.sh, and asserts the same exit code both ways (2 = denied,
# 0 = allowed).

# shellcheck disable=SC2016  # command strings are literal test input, never expanded here
# test-scope: plugins/guardrails/hooks/hooks.json plugins/guardrails/.claude-plugin/plugin.json
set -uo pipefail

HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GUARD_UNDER_TEST="$HOOK_DIR/block-cd-prefix.sh"
TEST_TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TEST_TMPDIR"' EXIT

# shellcheck source=guardrails-test-helpers.sh
source "$HOOK_DIR/guardrails-test-helpers.sh"
jq_crlf_free
unset CLAUDE_PLUGIN_OPTION_BLOCK_CD_PREFIX_ENABLED

REASON='Run `git -C <abs path> ...` with absolute paths instead of `cd`; for a multi-line commit message, Write the message to a file and use `git commit -F <file>`'
REASON_WRITE='Write to an absolute path, and run the command with its own directory option (for example `make -C <abs path>`) or an absolute path instead of `cd`'
NL=$'\n'

# deny_with <reason> <label> <command> [guard_invoke option ...]
deny_with() {
  local reason="$1" label="$2" command="$3" via
  shift 3
  for via in direct dispatched; do
    guard_invoke --via "$via" --command "$command" --cwd /srv/work/elsewhere "$@"
    assert_exit "$label ($via)" 2 "$GUARD_RC"
    assert_contains "$label ($via): reason" "$GUARD_ERR" "$reason"
  done
}

# deny <label> <command> [guard_invoke option ...]: denied with the git reason.
deny() { deny_with "$REASON" "$@"; }

# deny_write <label> <command> [guard_invoke option ...]: denied with the write reason.
deny_write() { deny_with "$REASON_WRITE" "$@"; }

# allow <label> <command> [guard_invoke option ...]
allow() {
  local label="$1" command="$2"
  shift 2
  expect_both "$label" 0 --command "$command" "$@"
}

# --- denied -------------------------------------------------------------------
deny "cd X && git status" 'cd X && git status'
deny "cd X; git commit -F f" 'cd X; git commit -F f'
deny "cd then a newline then git" "cd /repo${NL}git status"
deny "a tab after cd" $'cd\tX && git status'
deny "absolute cd operand" 'cd /srv/work/repo && git log --oneline'
deny "double-quoted operand with a space" 'cd "/srv/work/my repo" && git status'
deny "single-quoted operand" "cd '/srv/work/repo' && git status"
deny "git after an unrelated segment" 'cd X && npm ci && git add -A'
deny "git with an env prefix" 'cd X && GIT_PAGER=cat git log'
deny "git by path" 'cd X && /usr/bin/git status'
deny "heredoc commit message" "cd X && git commit -F - <<'EOF'${NL}subject${NL}EOF"
deny_write "write to a relative path" 'cd X && make > build.log'
deny_write "append to a relative path" 'cd X; npm test >> out/test.log 2>&1'
deny "git writing to a relative path keeps the git reason" 'cd X && git log > out.txt'
deny "write then git keeps the git reason" 'cd X && make > build.log && git status'
deny "append then git keeps the git reason" 'cd X; npm test >> out/test.log; git add -A'
deny "git then a write keeps the git reason" 'cd X && git status && make > build.log'
deny "cd to a cwd that differs" 'cd /srv/work/repo && git status' --cwd /srv/work/other

# --- allowed ------------------------------------------------------------------
allow "cd . && git status" 'cd . && git status'
allow "cd ./ && git status" 'cd ./ && git status'
allow "git -C X status" 'git -C X status'
allow "git -C with an absolute path" 'git -C /srv/work/repo commit -F /tmp/msg.txt'
allow "cd to the payload cwd" 'cd /srv/work/repo && git status' --cwd /srv/work/repo
allow "cd to the payload cwd, trailing slash" 'cd /srv/work/repo/ && git status' --cwd /srv/work/repo
allow "cd then no git and no write" 'cd X && npm test'
allow "cd then absolute writes and an fd dup" 'cd X && npm test > /tmp/out.log 2>&1'
allow "cd then a write to /dev/null" 'cd X && make >/dev/null'
allow "cd then a write under a variable" 'cd X && make > "$TMPDIR/build.log"'
allow "cd then a quoted >" 'cd X && echo "a > b"'
allow "cd then git inside quotes" 'cd X && echo "git status"'
allow "cd joined by ||" 'cd X || git status'
allow "cd piped" 'cd X | git status'
allow "cd not first" 'git status && cd X && git log'
allow "cd in quoted text" 'echo "cd X && git status"'
allow "cd with no operand" 'cd && git status'
allow "cdk is not cd" 'cdk deploy && git status'
allow "plain git" 'git status'
allow "PowerShell tool" 'cd X; git status' --tool PowerShell

# --- kill switch --------------------------------------------------------------
expect_both "kill switch off: allowed" 0 --command 'cd X && git status' \
  -- CLAUDE_PLUGIN_OPTION_BLOCK_CD_PREFIX_ENABLED=false

# --- registration -------------------------------------------------------------
row=$(jq -r '.hooks.PreToolUse[] | select(.matcher == "Bash|PowerShell") | .hooks[].args | map(tostring) | join(" ")' "$HOOK_DIR/hooks.json")
assert_contains "hooks.json runs the guard on the Bash|PowerShell row" "$row" " block-cd-prefix.sh"
assert_eq "plugin.json declares the kill switch, default on" "true" \
  "$(jq -r '.userConfig.block_cd_prefix_enabled.default' "$HOOK_DIR/../.claude-plugin/plugin.json")"

report
