#!/usr/bin/env bash
# Contract test for block-github-post-content.sh (guardrails plugin).
#
# Black-box: invokes the hook as a subprocess with a PreToolUse payload on
# stdin and asserts on the exit code (2 = blocked, 0 = allowed), alone and
# under the dispatcher behind block-fix-request-post, which reads the same
# bodies through the shared library.

# shellcheck disable=SC2016  # command strings are literal test input, never expanded here
# test-scope: plugins/guardrails/.claude-plugin/plugin.json
set -uo pipefail

HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="$HOOK_DIR/block-github-post-content.sh"
TEST_TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TEST_TMPDIR"' EXIT

# shellcheck source=guardrails-test-helpers.sh
source "$HOOK_DIR/guardrails-test-helpers.sh"
jq_crlf_free
unset CLAUDE_PLUGIN_OPTION_BLOCK_GITHUB_POST_CONTENT_ENABLED CLAUDE_PROJECT_DIR \
  CLAUDE_PLUGIN_OPTION_SECRET_PATTERN_DETECTION_ENABLED CLAUDE_PLUGIN_OPTION_HARDCODED_PATH_CHECK_ENABLED

# Runtime-constructed obviously-fake values (never a literal joined string).
GH_PREFIX='ghp_'
TOK="${GH_PREFIX}$(printf 'x%.0s' {1..36})"
HOME_PATH="/ho""me/alice/repos/project/notes.md"
WRAP="bash /ho""me/alice/.work/gate.sh run lane-key --"

WD="$TEST_TMPDIR/wd"
mkdir -p "$WD"
printf 'Rotated the token: %s\n' "$TOK" >"$WD/secret.md"
printf 'See %s for the log.\n' "$HOME_PATH" >"$WD/path.md"
printf 'Looks good to me.\n' >"$WD/plain.md"

payload() {
  jq -n --arg t "$1" --arg c "$2" --arg d "$WD" '{tool_name:$t,cwd:$d,tool_input:{command:$c}}'
}

verdict() {
  local rd=0 rr=0
  OUT_D=$(bash "$HOOK" <<<"$1" 2>&1) || rd=$?
  OUT_R=$(bash "$HOOK_DIR/run-guards.sh" block-fix-request-post.sh block-github-post-content.sh <<<"$1" 2>&1) || rr=$?
  RCS="$rd $rr"
}

# deny <label> <command> <secret|path> [tool]
deny() {
  verdict "$(payload "${4:-Bash}" "$2")"
  assert_eq "deny: $1 (direct, dispatched)" "2 2" "$RCS"
  if [[ "$3" == secret ]]; then
    assert_contains "deny: $1 -> names the class" "$OUT_D" "GitHub PAT"
    if [[ "$OUT_D$OUT_R" == *"$TOK"* ]]; then
      bad "deny: $1 -> the reason echoes the secret value"
    else
      ok "deny: $1 -> the reason never echoes the value"
    fi
  else
    assert_contains "deny: $1 -> names the path class" "$OUT_D" "path detected"
  fi
}

# quiet <label> <command> [tool]
quiet() {
  verdict "$(payload "${3:-Bash}" "$2")"
  assert_eq "quiet: $1 (direct, dispatched)" "0 0" "$RCS"
}

# --- secrets ------------------------------------------------------------------
deny "gh pr comment --body" "gh pr comment 12 --body \"token $TOK\"" secret
deny "gate.sh-wrapped gh pr comment --body" "$WRAP gh pr comment 12 -R o/r --body \"token $TOK\"" secret
deny "gate.sh batch, second command" "bash ./gate.sh batch k -- gh pr edit 1 --add-label x +++ gh issue comment 3 --body 'x $TOK'" secret
deny "wrapper script run by path" "./wrap.sh call -- gh pr comment 12 --body '$TOK'" secret
deny "gh pr comment --body-file" "gh pr comment 12 --body-file secret.md" secret
deny "heredoc to --body-file -" "gh pr comment 12 --body-file - <<'EOF'
note $TOK
EOF" secret
deny "\$(cat <<EOF) inside --body" "gh pr create --title t --body \"\$(cat <<'EOF'
## Summary
$TOK
EOF
)\"" secret
deny "gh api -f body=" "gh api repos/o/r/issues/1/comments -f body='$TOK'" secret
deny "curl with short flags written together" "curl -sSd '{\"body\":\"$TOK\"}' https://api.github.com/repos/o/r/issues/1/comments" secret
deny "curl POST to the API" "curl -X POST https://api.github.com/repos/o/r/issues/1/comments -d '{\"body\":\"$TOK\"}'" secret
deny "bash -c wrapper" "bash -c 'gh pr comment 1 --body \"$TOK\"'" secret
deny "PowerShell gh pr comment" "gh pr comment 12 --body '$TOK'" secret PowerShell

# --- machine paths -----------------------------------------------------------
deny "gh pr comment --body naming a home path" "gh pr comment 12 --body 'log at $HOME_PATH'" path
deny "body file naming a home path" "gh pr comment 12 --body-file path.md" path
deny "wrapped heredoc naming a home path" "$WRAP gh issue comment 3 --body-file - <<'EOF'
see $HOME_PATH
EOF" path

# --- stays quiet -------------------------------------------------------------
quiet "clean body" "gh pr comment 12 --body 'Looks good to me.'"
quiet "gate.sh-wrapped clean body under a home-dir wrapper path" "$WRAP gh pr comment 12 --body 'Looks good.'"
quiet "absolute --body-file holding a clean body" "$WRAP gh pr comment 12 --body-file $WD/plain.md"
# A body file that does not exist yet sends the whole command to the secret
# scan; its home-dir operand must still not reach the path scan.
quiet "home-dir --body-file operand" "$WRAP gh pr comment 12 --body-file /ho""me/alice/body.md"
quiet "token in a command that posts nothing" "grep -rn '$TOK' ."
quiet "token in an env prefix, not the body" "GH_TOKEN=$TOK gh pr comment 12 --body 'ok'"
quiet "token in a gh api GET" "gh api repos/o/r/issues -X GET -f q='$TOK'"
quiet "home path in a read-only gh call" "gh pr view 12 --json body --jq '.body' > $HOME_PATH"
quiet "home path in a here-doc that feeds another command, not the post" "python3 - <<'EOF'
print(open('$HOME_PATH').read())
EOF
gh pr comment 12 --body 'done'"
quiet "hosted-runner path in a quoted CI log" "gh pr comment 12 --body 'CI failed: /ho""me/runner/work/r/r/x.sh: line 3: unbound variable'"
quiet "token sent to another host" "curl -d '$TOK' https://example.test/hook"

# --- switches and input ------------------------------------------------------
rc=0
CLAUDE_PLUGIN_OPTION_BLOCK_GITHUB_POST_CONTENT_ENABLED=false bash "$HOOK" <<<"$(payload Bash "gh pr comment 1 --body '$TOK'")" >/dev/null 2>&1 || rc=$?
assert_exit "kill switch false disables the guard" 0 "$rc"
rc=0
CLAUDE_PLUGIN_OPTION_SECRET_PATTERN_DETECTION_ENABLED=false bash "$HOOK" <<<"$(payload Bash "gh pr comment 1 --body '$TOK'")" >/dev/null 2>&1 || rc=$?
assert_exit "secret_pattern_detection_enabled false turns off the secret half" 0 "$rc"
rc=0
CLAUDE_PLUGIN_OPTION_HARDCODED_PATH_CHECK_ENABLED=false bash "$HOOK" <<<"$(payload Bash "gh pr comment 1 --body '$HOME_PATH'")" >/dev/null 2>&1 || rc=$?
assert_exit "hardcoded_path_check_enabled false turns off the path half" 0 "$rc"
default=$(jq -r '.userConfig.block_github_post_content_enabled.default' "$HOOK_DIR/../.claude-plugin/plugin.json")
assert_eq "plugin.json default matches the script fallback" "true" "$default"
rc=0
bash "$HOOK" </dev/null >/dev/null 2>&1 || rc=$?
assert_exit "empty stdin is a skip" 0 "$rc"
rc=0
bash "$HOOK" <<<"not json" >/dev/null 2>&1 || rc=$?
assert_exit "text that is not JSON fails closed" 2 "$rc"
rc=0
bash "$HOOK" <<<"$(payload Bash "gh pr comment 1 --body '$TOK' $(printf 'x%.0s' {1..17000})")" >/dev/null 2>&1 || rc=$?
assert_exit "an over-length post holding a secret is refused" 2 "$rc"

report
