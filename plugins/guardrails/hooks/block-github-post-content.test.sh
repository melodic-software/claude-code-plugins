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
deny "body value starting with -H" "gh pr comment 12 --body '-Hi, the token is $TOK'" secret
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
printf 'Summary.\n' >"$WD/s"
deny "home path in the body, same path read by cat elsewhere" "cat $HOME_PATH && gh pr comment 12 --body 'Notes are at $HOME_PATH'" path
deny "home path in the title beside a short body-file name" "gh pr create --title 'Fix /Use""rs/alice/x' --body-file s" path
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
quiet "generic Windows checkout root in a bug report" "gh pr comment 12 --body 'Reproduced on the Windows lane in D:\\re""pos\\claude-code-plugins: the hook exits 2.'"
quiet "home-dir body file through a quoted \$(cat)" "gh pr comment 12 --body \"\$(cat /ho""me/alice/r/.tmp/body.md)\""
deny "single-quoted \$(cat home path) posted as written" "gh pr comment 12 --body 'To repost: gh pr comment 12 --body \"\$(cat /ho""me/alice/repo/.tmp/body.md)\"'" path
quiet "home-dir body file joined to curl -d@" "curl -d@/ho""me/alice/r/body.json https://api.github.com/repos/o/r/issues/1/comments"
quiet "token in an Authorization header, clean body" "curl -X POST -H 'Authorization: Bearer $TOK' -d '{\"body\":\"Looks good\"}' https://api.github.com/repos/o/r/issues/1/comments"
quiet "token sent to another host" "curl -d '$TOK' https://example.test/hook"

# --- --attach ----------------------------------------------------------------
# gh uploads an --attach file and posts its alt text (after `#`) or its base
# name, never its directory.
AHP="/ho""me/alice/wt"
AWP='C:\Use''rs\alice\wt'
quiet "attach beside a body file" "gh pr edit 5340 --repo o/r --body-file plain.md --attach $AHP/evidence/figma/built-banner-resized.png"
quiet "attach with alt text" "gh pr comment 5340 --body 'see shot' --attach '$AHP/evidence/a.png#Banner before resize'"
quiet "attach with a comma in the alt text" "gh pr comment 5340 --body 'see shot' --attach '$AHP/a.png#Banner, before resize'"
quiet "attach joined with =" "gh pr comment 5340 --body ok --attach=$AHP/evidence/a.png"
quiet "attach twice on issue create" "gh issue create --title t --body ok --attach $AHP/a.png --attach $AHP/b.png"
quiet "attach beside a body in a variable" "gh pr comment 5340 --body \"\$X\" --attach $AHP/a.png"
quiet "attach in a gate.sh wrapper" "bash ./gate.sh run k -- gh pr comment 1 --body ok --attach $AHP/a.png"
quiet "attach in bash -c" "bash -c 'gh pr comment 1 --body ok --attach $AHP/a.png'"
quiet "attach on pr review" "gh pr review 5340 --body ok --attach $AHP/a.png"
quiet "attach of a single-quoted Windows home operand" "gh pr edit 5340 --body 'ok' --attach '$AWP\\a.png'" PowerShell
quiet "attach of a Windows home operand with alt text" "gh pr edit 5340 --body 'ok' --attach '$AWP\\a.png#shot'" PowerShell
PROJ="$TEST_TMPDIR/proj"
mkdir -p "$PROJ/evidence"
git init -q "$PROJ"
CLAUDE_PROJECT_DIR="$PROJ" quiet "attach under the project root" "gh pr edit 1 --body ok --attach $PROJ/evidence/a.png"
CLAUDE_PROJECT_DIR="$PROJ" quiet "attach under the project root with alt text" "gh pr edit 1 --body ok --attach '$PROJ/evidence/a.png#shot'"
CLAUDE_PROJECT_DIR="$PROJ" deny "the project root in attach alt text" "gh pr edit 1 --body ok --attach './x.png#built in $PROJ'" path
CLAUDE_PROJECT_DIR="$PROJ" deny "the project root in the body beside an attach" "gh pr edit 1 --body 'built in $PROJ' --attach $PROJ/evidence/a.png" path
deny "home path in attach alt text" "gh pr comment 1 --attach '$AHP/evidence/a.png#built at $AHP'" path
deny "attach adjacent alt home path" "gh pr comment 1 --attach './x.png#$AHP/alt'" path
deny "Windows home path in attach alt text" "gh pr edit 5340 --body 'ok' --attach '$AWP\\a.png#built in $AWP'" path PowerShell
deny "Windows home operand on Bash, posted whole as the base name" "gh pr comment 1 --attach '$AWP\\a.png'" path
deny "Windows home operand on Bash with an empty alt" "gh pr comment 1 --attach '$AWP\\a.png#'" path
deny "body file holding a home path beside an attach" "gh pr comment 5340 --body-file path.md --attach $AHP/a.png" path
deny "prose body naming the attached path" "gh pr comment 5340 --body 'see $AHP/a.png' --attach $AHP/a.png" path
deny "body equal to the attached path" "gh pr comment 5340 --body $AHP/a.png --attach $AHP/a.png" path
deny "markdown body reference to the attached path" "gh pr comment 5340 --body '![x]($AHP/a.png)' --attach $AHP/a.png" path
deny "look-alike --attachment flag" "gh pr comment 1 --body ok --attachment $AHP/a.png" path
deny "look-alike --attach-x= flag" "gh pr comment 1 --body ok --attach-x=$AHP/a.png" path
deny "body value spelled --attach=" "gh pr comment 1 --body '--attach=$AHP/a.png'" path
deny "--attach= word taken as the --body value" "gh pr comment 1 --body --attach=$AHP/a.png" path
deny "--attach= word taken as the -b value" "gh pr comment 1 -b --attach=$AHP/a.png" path
deny "--attach= word taken as the --title value" "gh issue create --body ok --title --attach=$AHP/a.png" path
# A word before a joined --attach= that vanishes or splits at run time leaves
# a value-taking flag right before it, which posts the whole word.
deny "joined attach after an empty variable" "gh pr comment 1 --body \$E --attach=$AHP/x.png" path
deny "joined attach after an IFS split" "gh issue create --title x\$IFS--body --attach=$AHP/x.png" path
deny "joined attach after a brace expansion" "gh issue create --title {x,--body} --attach=$AHP/x.png" path
deny "joined attach after an empty \"\$@\"" "gh pr comment 1 --body \"\$@\" --attach=$AHP/x.png" path
deny "joined attach after an empty backtick substitution" "gh pr comment 1 --body \`true\` --attach=$AHP/x.png" path
deny "joined attach after an empty \$( ) substitution" "gh pr comment 1 --body \$(true) --attach=$AHP/x.png" path
deny "joined attach after \$null" "gh pr comment 1 --body \$null --attach='$AWP\\x.png'" path PowerShell
deny "joined attach after an empty string PowerShell may drop" "gh pr comment 1 --body '' --attach='$AWP\\x.png'" path PowerShell
# Under PowerShell's legacy native argument passing an embedded `"` is not
# escaped, so it can split a word or join later words, the attach operand
# included, into one posted value.
deny "PowerShell double quote in the body before a joined attach" "gh pr comment 1 --body 'x\" \"--body' --attach='$AWP\\x.png'" path PowerShell
deny "PowerShell double quote in a spaced attach operand" "gh pr comment 1 --attach './x.png\" \"--body=$AWP\\log'" path PowerShell
deny "PowerShell double quote in a joined attach operand" "gh pr comment 1 --body ok --attach='./x.png\" \"--body=$AWP\\log'" path PowerShell
deny "PowerShell double quote in an earlier word of the segment" "gh pr comment 1 --body 'a\"b' --repo o/r --attach='$AWP\\x.png'" path PowerShell
deny "attach after a bool flag, judged whole" "gh pr create --draft --attach $AHP/x.png --title t --body ok" path
deny "attach operand holding a glob character" "gh pr comment 1 --body ok --attach $AHP/x*.png" path
deny "joined attach with a home path in the alt text" "gh pr comment 1 --body ok --attach='$AHP/x.png#built at $AHP'" path
quiet "joined attach after a flag written with =" "gh pr comment 1 --body=ok --attach=$AHP/x.png"
quiet "joined attach after a stdin body file" "gh pr comment 1 --body-file - --attach=$AHP/x.png"
deny "bare --attach ending a segment" "gh pr comment 1 --body ok --attach && gh pr comment 2 --body 'see $AHP/x/log.txt'" path
deny "attach operand brace-expanding to a body" "gh pr comment 1 --attach {./x.png,--body=$AHP/log}" path
deny "attach operand IFS-splitting to a body" "gh pr comment 1 --attach ./x.png\$IFS--body=$AHP/log" path
deny "attach operand with a backtick substitution splitting to a body" "gh pr comment 1 --attach ./x.png\`printf ' '\`--body=$AHP/log" path
deny "joined attach operand IFS-splitting to a body" "gh pr comment 1 --attach=./x.png\$IFS--body=$AHP/log" path
deny "PowerShell attach array carrying a body" "gh pr comment 1 --attach './x.png','--body=$AWP\\log'" path PowerShell
deny "token in attach alt text" "gh pr comment 1 --body ok --attach '$AHP/a.png#alt $TOK'" secret
deny "token in the attached file's name" "gh pr comment 1 --body ok --attach '$AHP/$TOK.png'" secret

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
# JSON whose fields jq cannot read gets past the stdin read and is refused by
# the field read. A NUL in a harmless command is refused there too.
guard_invoke --hook "$HOOK" --payload '{"tool_name":"Bash","tool_input":"gh pr comment 1"}'
assert_exit "a payload whose fields jq cannot read fails closed" 2 "$GUARD_RC"
assert_eq "unreadable fields: the refusal says why" \
  "BLOCKED: the hook payload could not be parsed." "$GUARD_ERR"
assert_eq "unreadable fields: nothing on stdout" "" "$GUARD_OUT"
guard_invoke --hook "$HOOK" --payload "$(jq -n '{tool_name:"Bash",tool_input:{command:"ls\u0000 -la"}}')"
assert_exit "a NUL byte in a harmless command fails closed" 2 "$GUARD_RC"
assert_eq "NUL byte: the refusal says why" \
  "BLOCKED: the payload carries a NUL byte. Reissue the call without it." "$GUARD_ERR"
assert_eq "NUL byte: nothing on stdout" "" "$GUARD_OUT"
rc=0
bash "$HOOK" <<<"$(payload Bash "gh pr comment 1 --body '$TOK' $(printf 'x%.0s' {1..17000})")" >/dev/null 2>&1 || rc=$?
assert_exit "an over-length post holding a secret is refused" 2 "$rc"

report
