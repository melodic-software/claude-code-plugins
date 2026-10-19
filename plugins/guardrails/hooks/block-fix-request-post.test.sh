#!/usr/bin/env bash
# Contract test for block-fix-request-post.sh (guardrails plugin).
#
# Black-box: invokes the hook as a subprocess with a PreToolUse payload on
# stdin and asserts on the exit code (2 = blocked, 0 = allowed). The phrase and
# its line rule come from FIX_REQUEST in
# .github/scripts/pr-unblock/address-feedback.mjs: a line that starts with
# `PR-fix lane: please fix this finding`, any case, outside a fence; a quoted
# (`>`) line never matches.
#
# Every stay-quiet case goes through `quiet`, which also asserts the input
# names the phrase, so a substring matcher would have blocked it.

# shellcheck disable=SC2016  # command strings are literal test input, never expanded here
set -uo pipefail

HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="$HOOK_DIR/block-fix-request-post.sh"
TEST_TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TEST_TMPDIR"' EXIT

# shellcheck source=guardrails-test-helpers.sh
source "$HOOK_DIR/guardrails-test-helpers.sh"
jq_crlf_free
unset CLAUDE_PLUGIN_OPTION_BLOCK_FIX_REQUEST_POST_ENABLED

P='PR-fix lane: please fix this finding'
F='```'
WD="$TEST_TMPDIR/wd"
mkdir -p "$WD"
printf 'Thanks for the review.\n%s\n' "$P" >"$WD/body.md"
printf 'Context.\n\n> %s\n\nThat quoted line is how the owner asks.\n' "$P" >"$WD/quoted.md"
printf '%s\n%s\n%s\n' "$F" "$P" "$F" >"$WD/fenced.md"
printf 'Looks good to me.\n' >"$WD/plain.md"
printf '{"body":"Context\\n%s"}\n' "$P" >"$WD/payload.json"
printf '{"body":"> %s"}\n' "$P" >"$WD/quoted.json"
printf 'mutation { addComment(input:{subjectId:"I_1", body:"%s"}) { clientMutationId } }\n' "$P" >"$WD/m.graphql"

# payload <tool> <command>: a payload whose cwd holds the fixture files.
payload() {
  jq -n --arg t "$1" --arg c "$2" --arg d "$WD" '{tool_name:$t,cwd:$d,tool_input:{command:$c}}'
}

N_DENY=0
N_QUIET=0

# verdict <payload>: the guard's exit code alone and under the dispatcher,
# behind block-no-verify so the dispatcher's shared parse is replayed to it,
# as "<direct> <dispatched>"; the deny reason of each lands in OUT_D / OUT_R.
verdict() {
  local rd=0 rr=0
  OUT_D=$(bash "$HOOK" <<<"$1" 2>&1) || rd=$?
  OUT_R=$(bash "$HOOK_DIR/run-guards.sh" block-no-verify.sh block-fix-request-post.sh <<<"$1" 2>&1) || rr=$?
  RCS="$rd $rr"
}

# deny <label> <command> [tool]
deny() {
  verdict "$(payload "${3:-Bash}" "$2")"
  assert_eq "deny: $1 (direct, dispatched)" "2 2" "$RCS"
  assert_contains "deny: $1 -> names the owner rule" "$OUT_D" "Only the repository owner may post a fix request, typed in the GitHub UI"
  assert_contains "deny: $1 -> cites the decision" "$OUT_D" "issues/8438"
  assert_contains "deny: $1 -> the dispatcher relays the reason" "$OUT_R" "issues/8438"
  N_DENY=$((N_DENY + 1))
}

# quiet <label> <command> [tool] [text a substring matcher would see]
quiet() {
  local hay="${4:-$2}"
  verdict "$(payload "${3:-Bash}" "$2")"
  assert_eq "quiet: $1 (direct, dispatched)" "0 0" "$RCS"
  if [[ "${hay,,}" == *"${P,,}"* ]]; then
    ok "quiet: $1 -> a substring matcher would have blocked it"
  else
    bad "quiet: $1 -> the input does not name the phrase, so it proves nothing about a substring matcher"
  fi
  N_QUIET=$((N_QUIET + 1))
}

# quiet_plain <label> <command>: stays quiet, and names no phrase at all.
quiet_plain() {
  verdict "$(payload Bash "$2")"
  assert_eq "quiet: $1 (direct, dispatched)" "0 0" "$RCS"
  N_QUIET=$((N_QUIET + 1))
}

# mcp <label> <tool> <tool_input JSON> <expected>
mcp() {
  verdict "$(jq -n --arg t "$2" --argjson i "$3" '{tool_name:$t,tool_input:$i}')"
  if (($4 == 2)); then
    assert_eq "deny: $1 (direct, dispatched)" "2 2" "$RCS"
    N_DENY=$((N_DENY + 1))
  else
    assert_eq "quiet: $1 (direct, dispatched)" "0 0" "$RCS"
    [[ "${3,,}" == *"${P,,}"* ]] && ok "quiet: $1 -> a substring matcher would have blocked it"
    N_QUIET=$((N_QUIET + 1))
  fi
}

# --- 1. The phrase inline in a posting command --------------------------------
deny "gh pr comment --body" "gh pr comment 12 --body \"$P\""
deny "gh pr comment -b, mixed case, trailing period" "gh pr comment 12 -b 'pr-fix LANE: Please fix this finding.'"
deny "gh pr comment --body=" "gh pr comment 12 --body=\"$P\""
deny "gh pr review --comment --body" "gh pr review 12 --comment --body \"$P\""
deny "gh issue comment, second line" "gh issue comment 5 --body \$'Thanks.\\n$P'"
deny "gh pr edit --body" "gh pr edit 12 --body \"$P\""
deny "gh pr create --body" "gh pr create --title t --body \"$P\""
deny "gh pr comment with the phrase escaped, not quoted" 'gh pr comment 12 --body PR-fix\ lane:\ please\ fix\ this\ finding'
deny "gh pr -R before the action" "gh pr -R o/r comment 12 --body \"$P\""
deny "gh api reply, -f body=" "gh api repos/o/r/pulls/comments/1/replies -f body='$P'"
deny "gh api edit, -X PATCH -F body=" "gh api -X PATCH repos/o/r/issues/comments/9 -F body=\"$P\""
deny "gh api --raw-field body=" "gh api repos/o/r/issues/1/comments --raw-field \"body=$P\""
deny "gh api graphql mutation, inline body" "gh api graphql -f query='mutation { addPullRequestReviewThreadReply(input:{pullRequestReviewThreadId:\"T_1\", body:\"$P\"}) { comment { id } } }'"
deny "gh api graphql mutation, body in a variable" "gh api graphql -f query='mutation(\$b:String!){ addComment(input:{subjectId:\"I_1\", body:\$b}) { clientMutationId } }' -f b='$P'"
deny "curl REST JSON body" "curl -s -X POST -H 'Authorization: Bearer x' https://api.github.com/repos/o/r/issues/1/comments -d '{\"body\":\"$P\"}'"
deny "curl REST JSON body, after an escaped newline" "curl -s https://api.github.com/repos/o/r/issues/1/comments --data '{\"body\":\"Context\\n$P\"}'"
deny "curl GraphQL mutation" "curl -s https://api.github.com/graphql -d '{\"query\":\"mutation { addComment(input:{subjectId:\\\"I_1\\\", body:\\\"$P\\\"}) { clientMutationId } }\"}'"
deny "curl to a GHES /api/v3 route" "curl -s https://ghe.example.com/api/v3/repos/o/r/issues/1/comments -d '{\"body\":\"$P\"}'"
deny "curl form-encoded body" "curl -s https://api.github.com/repos/o/r/issues/1/comments --data-urlencode 'body=PR-fix lane%3A please fix this finding'"
deny "bash -c wrapper" "bash -c \"gh pr comment 12 --body '$P'\""
deny "eval" "eval \"gh pr comment 12 --body '$P'\""
deny "env and an assignment before gh" "GH_REPO=o/r env gh pr comment 12 --body \"$P\""
deny "after another command" "cd /tmp && gh pr comment 12 --body \"$P\""
deny "hidden in an HTML comment (the lane still reads it)" "gh pr comment 12 --body \$'<!--\\n$P\\n-->'"
deny "~~~ fence closed by a backtick fence (the lane's toggle)" "gh pr comment 12 --body \$'~~~\\n$F\\n$P\\n$F\\n~~~'"
deny "PowerShell: gh pr comment" "gh pr comment 12 --body \"$P\"" PowerShell

# --- 2. The phrase in a file the command reads ----------------------------------
deny "gh pr comment --body-file" "gh pr comment 12 --body-file body.md"
deny "gh pr comment -F" "gh pr comment 12 -F body.md"
deny "gh pr comment --body-file with an absolute path" "gh pr comment 12 --body-file $WD/body.md"
deny "gh issue comment --body-file=" "gh issue comment 5 --body-file=body.md"
deny "gh pr review -F" "gh pr review 12 --request-changes -F body.md"
deny "gh api -F body=@file" "gh api repos/o/r/issues/1/comments -F body=@body.md"
deny "gh api --input JSON file" "gh api repos/o/r/issues/1/comments --input payload.json"
deny "gh api graphql query from a file" "gh api graphql -F query=@m.graphql"
deny "curl -d @file" "curl -s https://api.github.com/repos/o/r/issues/1/comments -d @payload.json"
deny "body through \$(cat file)" "gh pr comment 12 --body \"\$(cat body.md)\""
deny "body piped from cat" "cat body.md | gh pr comment 12 --body-file -"
deny "body from a < redirect" "gh pr comment 12 --body-file - < body.md"

# --- 3. Heredoc bodies -----------------------------------------------------------
deny "--body-file - from a heredoc" "gh pr comment 12 --body-file - <<'EOF'
See above.
$P
EOF"
deny "\$(cat <<EOF) inside --body" "gh pr comment 12 --body \"\$(cat <<'EOF'
$P
EOF
)\""
deny "gh api --input - from a heredoc" "gh api repos/o/r/issues/1/comments --input - <<'EOF'
{\"body\":\"$P\"}
EOF"
deny "curl -d @- from a heredoc" "curl -s https://api.github.com/repos/o/r/issues/1/comments -d @- <<'EOF'
{\"body\":\"Context\\n$P\"}
EOF"

# --- 3b. A fence only the guard would see (review on #8448) ------------------
# The lane opens a fence only on a line starting with up to three spaces and
# ``` or ~~~ (address-feedback.mjs isFixRequest), so a marker after `x=` or a
# quote is no fence to it.
deny "body word with a marker after x=" "gh pr comment 12 --body \$'x=$F\\n$P'"
deny "echo of a fence before a heredoc body" "echo \"$F\"
gh pr comment 12 -F - <<EOF
$P
EOF"
mcp "MCP add_issue_comment, marker after x=" mcp__github__add_issue_comment "{\"body\":\"x=$F\\n$P\"}" 2
deny "unquoted \$(cat file) as the body" "gh pr comment 12 --body \$(cat body.md)"
deny "backtick cat as the body" "gh pr comment 12 --body \`cat body.md\`"
deny "here-string fed to --input -" "gh api repos/o/r/issues/1/comments --input - <<< '{\"body\":\"$P\"}'"

# --- 4. The GitHub MCP server's write tools -------------------------------------
mcp "MCP add_issue_comment" mcp__github__add_issue_comment "{\"owner\":\"o\",\"repo\":\"r\",\"issue_number\":1,\"body\":\"$P\"}" 2
mcp "MCP add_reply_to_pull_request_comment, plugin server" mcp__plugin_github_github__add_reply_to_pull_request_comment "{\"body\":\"Done.\\n$P\"}" 2
mcp "MCP pull_request_review_write" mcp__github__pull_request_review_write "{\"method\":\"create\",\"body\":\"$P\"}" 2
mcp "MCP create_pull_request_review, inline comment" mcp__github__create_pull_request_review "{\"body\":\"ok\",\"comments\":[{\"path\":\"a\",\"body\":\"$P\"}]}" 2
mcp "MCP add_issue_comment, quoted line" mcp__github__add_issue_comment "{\"body\":\"> $P\"}" 0
mcp "MCP add_issue_comment, fenced" mcp__github__add_issue_comment "{\"body\":\"$F\\n$P\\n$F\"}" 0
mcp "MCP add_issue_comment, no phrase" mcp__github__add_issue_comment '{"body":"Thanks."}' 0

# --- 5. Reading, grepping or showing the phrase (allowed) -----------------------
quiet "grep for the phrase" "grep -n \"$P\" .github/scripts/pr-unblock/address-feedback.mjs"
quiet "rg for the phrase" "rg -n '$P' ."
quiet "git log --grep" "git log --oneline --grep \"$P\""
quiet "git commit -m naming the phrase" "git commit -m \"$P\""
quiet "echo of the phrase" "echo \"$P\""
quiet "gh search for the phrase" "gh search issues \"$P\""
quiet "gh api GET with a jq filter on the phrase" "gh api repos/o/r/issues/1/comments --jq '.[] | select(.body | test(\"$P\"))'"
quiet "gh api -X GET with the phrase as a query field" "gh api -X GET search/issues -f q='$P'"
quiet "gh api graphql query, not a mutation" "gh api graphql -f query='query { search(query: \"$P\", type: ISSUE, first: 5) { issueCount } }'"
quiet "curl to another host" "curl -s https://example.com/hook -d 'body=$P'"
quiet "curl GET of a GitHub search" "curl -s -G https://api.github.com/search/issues --data-urlencode 'q=$P'"
quiet "rg of the phrase, then an unrelated post (review on #8448)" "rg -n \"$P\" .github/scripts/pr-unblock/address-feedback.mjs; gh pr comment 12 --body \"Thanks, fixed.\""
quiet "git log --grep of the phrase, then a post from a plain file" "git log --oneline --grep \"$P\" && gh pr comment 12 --body-file plain.md"
quiet_plain "git show" "git show HEAD -- .github/scripts/pr-unblock/address-feedback.mjs"
quiet_plain "gh pr view" "gh pr view 12 --comments"

# --- 6. Posting without a request line (allowed) --------------------------------
quiet_plain "gh pr comment with no phrase" 'gh pr comment 12 --body "Looks good."'
quiet_plain "gh pr comment --body-file with no phrase" "gh pr comment 12 --body-file plain.md"
quiet "phrase mid-line" "gh pr comment 12 --body \"The lane acts on a line that starts with $P, typed by the owner.\""
quiet "phrase after > " "gh pr comment 12 --body \$'> $P\\nThat quoted line is the owner\\'s.'"
quiet "phrase inside a fence" "gh pr comment 12 --body \$'$F\\n$P\\n$F'"
quiet "phrase inside a ~~~ fence" "gh pr comment 12 --body \$'~~~\\n$P\\n~~~'"
quiet "phrase followed by a word character" "gh pr comment 12 --body \"${P}s\""
quiet "--body-file with the phrase quoted" "gh pr comment 12 --body-file quoted.md" Bash "$(<"$WD/quoted.md")"
quiet "--body-file with the phrase fenced" "gh pr comment 12 --body-file fenced.md" Bash "$(<"$WD/fenced.md")"
quiet "gh api --input JSON with the phrase quoted" "gh api repos/o/r/issues/1/comments --input quoted.json" Bash "$(<"$WD/quoted.json")"
quiet "curl JSON with the phrase quoted" "curl -s https://api.github.com/repos/o/r/issues/1/comments -d '{\"body\":\"> $P\"}'"
quiet "heredoc body with the phrase quoted" "gh pr comment 12 --body-file - <<'EOF'
> $P
EOF"

# --- 7. Other tools, and the kill switch --------------------------------------
rc=0
bash "$HOOK" <<<"$(jq -n --arg c "$P" '{tool_name:"Write",tool_input:{file_path:"a.md",content:$c}}')" >/dev/null 2>&1 || rc=$?
assert_exit "quiet: a Write payload carrying the phrase (Write and Edit are not in scope)" 0 "$rc"
N_QUIET=$((N_QUIET + 1))
rc=0
CLAUDE_PLUGIN_OPTION_BLOCK_FIX_REQUEST_POST_ENABLED=false bash "$HOOK" <<<"$(payload Bash "gh pr comment 12 --body \"$P\"")" >/dev/null 2>&1 || rc=$?
assert_exit "kill switch false disables the guard" 0 "$rc"
rc=0
CLAUDE_PLUGIN_OPTION_BLOCK_FIX_REQUEST_POST_ENABLED=maybe bash "$HOOK" <<<"$(payload Bash "gh pr comment 12 --body \"$P\"")" >/dev/null 2>&1 || rc=$?
assert_exit "kill switch typo keeps the guard on" 2 "$rc"
pj_default=$(jq -r '.userConfig.block_fix_request_post_enabled.default' "$HOOK_DIR/../.claude-plugin/plugin.json")
assert_eq "plugin.json default matches the script fallback" true "$pj_default"

# --- 8. Inputs -----------------------------------------------------------------
rc=0
bash "$HOOK" </dev/null >/dev/null 2>&1 || rc=$?
assert_exit "empty stdin is a skip" 0 "$rc"
rc=0
bash "$HOOK" <<<'not json' >/dev/null 2>&1 || rc=$?
assert_exit "text that is not JSON fails closed" 2 "$rc"
rc=0
bash "$HOOK" <<<"$(payload Bash "gh pr comment 12 --body \"$P\" $(printf 'x%.0s' {1..17000})")" >/dev/null 2>&1 || rc=$?
assert_exit "an over-length command naming the phrase is refused" 2 "$rc"
rc=0
bash "$HOOK" <<<"$(payload Bash "echo $(printf 'x%.0s' {1..17000})")" >/dev/null 2>&1 || rc=$?
assert_exit "an over-length command without the phrase is left to the row's ceiling" 0 "$rc"

echo "cases: deny=$N_DENY quiet=$N_QUIET"
report
