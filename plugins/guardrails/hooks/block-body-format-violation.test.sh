#!/usr/bin/env bash

# shellcheck disable=SC2016  # command strings are literal test input, never expanded here
# test-scope: plugins/guardrails/.claude-plugin/plugin.json plugins/guardrails/lib/github-post/github-post-body.sh plugins/guardrails/hooks/hooks.json
set -uo pipefail

HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="$HOOK_DIR/block-body-format-violation.sh"
TEST_TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TEST_TMPDIR"' EXIT

# shellcheck source=guardrails-test-helpers.sh
source "$HOOK_DIR/guardrails-test-helpers.sh"
jq_crlf_free
unset CLAUDE_PLUGIN_OPTION_BLOCK_BODY_FORMAT_VIOLATION_ENABLED CLAUDE_PROJECT_DIR

mkrepo() {
  local d="$TEST_TMPDIR/$1"
  mkdir -p "$d/docs/conventions" "$d/.github/workflows"
  git init -q "$d"
  git -C "$d" remote add origin "https://github.com/acme/$1.git"
  printf 'docs/conventions/**/*.local.*\n' >"$d/.gitignore"
  if [[ -n "$2" ]]; then
    printf '%s\n' "$2" >"$d/docs/conventions/source-control.yaml"
    git -C "$d" add docs/conventions/source-control.yaml
  fi
  printf 'jobs:\n  c:\n    steps:\n      - uses: ./.github/actions/pr-require-checks/check-contract\n' >"$d/.github/workflows/ci.yml"
  printf '%s' "$d"
}

FULL=$(mkrepo widgets $'pr_body_required_sections:\n  - Summary\n  - Fix\nlinkage_gate_uses_pattern: \'pr-require-checks/check-contract\'')
NONE=$(mkrepo plain "")
NOKEY=$(mkrepo nokey 'pr_open_state: ready')
NONEKW=$(mkrepo nonekw 'pr_body_required_sections: none')
BRIEF=$(mkrepo brief 'pr_body_required_sections: briefing')
OFF=$(mkrepo off $'pr_body_required_sections:\n  - Summary\npr_body_format_gate: false')
LOCALOFF=$(mkrepo localoff $'pr_body_required_sections:\n  - Summary')
printf 'pr_body_format_gate: false\n' >"$LOCALOFF/docs/conventions/source-control.local.yaml"

GOOD=$'Closes #12\n\n## Summary\nWhy it changes.\n\n## Fix\nWhat changed.'
NOFIX=$'Closes #12\n\n## Summary\nWhy it changes.'
EMPTYFIX=$'Refs: #12\n\n## Summary\nWhy.\n\n## Fix\n\n## Notes\nx'
NOOPEN=$'## Summary\nWhy.\n\n## Fix\nWhat.'
FENCED=$'No related issue: a test\n\n## Summary\nWhy.\n\n~~~\n## Fix\nnot real\n~~~'
printf '%s\n' "$GOOD" >"$FULL/good.md"
printf '%s\n' "$NOFIX" >"$FULL/nofix.md"
printf '%s\n' 'Closes #12' '' '## Summary' 'Why.' '' '````markdown' 'An unclosed example:' '```bash' 'echo hi' '````' '' '## Fix' 'What changed.' >"$FULL/nested-fence.md"
printf '%s\n' 'Closes #12' '' '## Summary' 'Why.' '' '~~~' '```' '## Fix' 'inside' '~~~~' >"$FULL/mixed-fence.md"

payload() {
  jq -n --arg t "${3:-Bash}" --arg c "$1" --arg d "$2" '{tool_name:$t,cwd:$d,tool_input:{command:$c}}'
}

verdict() {
  local rd=0 rr=0
  OUT_D=$(bash "$HOOK" <<<"$1" 2>&1) || rd=$?
  OUT_R=$(bash "$HOOK_DIR/run-guards.sh" block-body-format-violation.sh <<<"$1" 2>&1) || rr=$?
  RCS="$rd $rr"
}

deny() {
  verdict "$(payload "$2" "$3")"
  assert_eq "deny: $1 (direct, dispatched)" "2 2" "$RCS"
  assert_contains "deny: $1 -> names what is missing" "$OUT_D" "$4"
  assert_contains "deny: $1 -> the dispatcher relays it" "$OUT_R" "$4"
}

pass() {
  verdict "$(payload "$2" "$3" "${4:-Bash}")"
  assert_eq "pass: $1 (direct, dispatched)" "0 0" "$RCS"
}

q() { printf '%q' "$1"; }

pass "--body, compliant" "gh pr create --title t --body $(q "$GOOD")" "$FULL"
deny "--body, a section missing" "gh pr create --title t --body $(q "$NOFIX")" "$FULL" 'Missing a "## Fix" section: add the heading "## Fix"'
deny "--body=, a section missing" "gh pr create --title t --body=$(q "$NOFIX")" "$FULL" 'Missing a "## Fix" section'
deny "-b, a section missing" "gh pr create -t t -b $(q "$NOFIX")" "$FULL" 'Missing a "## Fix" section'
deny "--body, an empty section" "gh pr create --title t --body $(q "$EMPTYFIX")" "$FULL" 'The "## Fix" section is empty'
deny "--body, no opener" "gh pr create --title t --body $(q "$NOOPEN")" "$FULL" 'does not open with a linkage line'
assert_contains "the opener refusal names its source" "$OUT_D" "linkage_gate_uses_pattern in docs/conventions/source-control.yaml, matched by .github/workflows/ci.yml"
assert_contains "the refusal names the off switch" "$OUT_D" "pr_body_format_gate: false"
assert_contains "the refusal names the target repository" "$OUT_D" "acme/widgets"
deny "--body, a bare Refs without its colon" "gh pr create --title t --body $(q $'Refs #12\n\n## Summary\nx\n\n## Fix\ny')" "$FULL" 'does not open with a linkage line'
pass "--body, Fixed: and an owner/repo reference" "gh pr create --title t --body $(q $'Fixed: acme/widgets#12\n\n## Summary\nx\n\n## Fix\ny')" "$FULL"
deny "--body, a heading only inside a fence" "gh pr create --title t --body $(q "$FENCED")" "$FULL" 'Missing a "## Fix" section'
pass "a four-backtick fence holding a three-backtick example closes only on its own delimiter" "gh pr create --title t --body-file nested-fence.md" "$FULL"
deny "a tilde fence closes only on tildes at least as long, so a heading inside it stays hidden" "gh pr create --title t --body-file mixed-fence.md" "$FULL" 'Missing a "## Fix" section'
pass "--body-file, compliant""gh pr create --title t --body-file good.md" "$FULL"
deny "--body-file, a section missing" "gh pr create --title t --body-file nofix.md" "$FULL" 'Missing a "## Fix" section'
deny "-F, a section missing" "gh pr create --title t -F $FULL/nofix.md" "$FULL" 'Missing a "## Fix" section'
pass "--body-file, a file the command writes first" "printf x > nofix.md && gh pr create --title t --body-file nofix.md" "$FULL"
pass '--body "$(cat <<EOF)", compliant' "gh pr create --title t --body \"\$(cat <<'EOF'"$'\n'"$GOOD"$'\n'"EOF"$'\n'")\"" "$FULL"
deny '--body "$(cat <<EOF)", a section missing' "gh pr create --title t --body \"\$(cat <<'EOF'"$'\n'"$NOFIX"$'\n'"EOF"$'\n'")\"" "$FULL" 'Missing a "## Fix" section'
deny '--body "$(cat file)", a section missing' 'gh pr create --title t --body "$(cat nofix.md)"' "$FULL" 'Missing a "## Fix" section'
pass "--body-file - with a heredoc, compliant" "gh pr create --title t --body-file - <<'EOF'"$'\n'"$GOOD"$'\n'"EOF" "$FULL"
deny "--body-file - with a heredoc, a section missing" "gh pr create --title t --body-file - <<'EOF'"$'\n'"$NOFIX"$'\n'"EOF" "$FULL" 'Missing a "## Fix" section'
deny "gh pr edit --body, a section missing" "gh pr edit 5 --body $(q "$NOFIX")" "$FULL" 'Missing a "## Fix" section'
pass "gh pr edit without a body" "gh pr edit 5 --title t --add-label x" "$FULL"
pass "gh pr create --fill" "gh pr create --fill" "$FULL"
pass "a body in a variable" 'gh pr create --title t --body "$B"' "$FULL"
pass "gh issue create: no key declares an issue format" "gh issue create --title t --body $(q "$NOOPEN")" "$FULL"
pass "gh pr comment" "gh pr comment 5 --body $(q "$NOOPEN")" "$FULL"
deny "-R naming this repository" "gh pr create -R acme/widgets --title t --body $(q "$NOFIX")" "$FULL" 'Missing a "## Fix" section'
deny "-R before the action, naming this repository" "gh pr -R Acme/Widgets create --title t --body $(q "$NOFIX")" "$FULL" 'Missing a "## Fix" section'
pass "gh pr edit with a PR URL of another repository" "gh pr edit https://github.com/other/repo/pull/12 --body $(q "$NOFIX")" "$FULL"
deny "gh pr edit with a PR URL of this repository" "gh pr edit https://github.com/Acme/widgets/pull/12 --body $(q "$NOFIX")" "$FULL" 'Missing a "## Fix" section'
pass "a PR URL of another repository beside -R naming this one" "gh pr edit -R acme/widgets https://github.com/other/repo/pull/12 --body $(q "$NOFIX")" "$FULL"
deny "a body that is only a PR URL is a body, not a target" "gh pr edit 5 --body https://github.com/other/repo/pull/12" "$FULL" 'Missing a "## Summary" section'
pass "-R naming another repository""gh pr create -R other/repo --title t --body $(q "$NOFIX")" "$FULL"
pass "after a cd" "cd /tmp && gh pr create --title t --body $(q "$NOFIX")" "$FULL"
pass "PowerShell" "gh pr create --title t --body 'x'" "$FULL" PowerShell
pass "a repository that declares no format" "gh pr create --title t --body x" "$NONE"
pass "a team file without the key" "gh pr create --title t --body x" "$NOKEY"
pass "pr_body_required_sections: none" "gh pr create --title t --body x" "$NONEKW"
deny "briefing preset" "gh pr create --title t --body $(q $'## Why\nx\n## What changed\ny')" "$BRIEF" 'Missing a "## Scope" section'
pass "briefing preset, compliant" "gh pr create --title t --body $(q $'## Why\nx\n## What changed\ny\n## Scope\nz\n## Verification\nv')" "$BRIEF"
pass "the team layer turns the gate off" "gh pr create --title t --body x" "$OFF"
pass "the personal override turns the gate off" "gh pr create --title t --body x" "$LOCALOFF"
git -C "$LOCALOFF" add -f docs/conventions/source-control.local.yaml
deny "a tracked personal override is not read" "gh pr create --title t --body x" "$LOCALOFF" 'Missing a "## Summary" section'
assert_contains "a tracked personal override is named" "$OUT_D" "is not ignored by git"

CLAUDE_PLUGIN_OPTION_BLOCK_BODY_FORMAT_VIOLATION_ENABLED=false
export CLAUDE_PLUGIN_OPTION_BLOCK_BODY_FORMAT_VIOLATION_ENABLED
pass "the userConfig switch turns the guard off" "gh pr create --title t --body $(q "$NOFIX")" "$FULL"
unset CLAUDE_PLUGIN_OPTION_BLOCK_BODY_FORMAT_VIOLATION_ENABLED

mcp() {
  jq -n --arg t "mcp__plugin_github_github__$1" --arg b "$2" --arg o "$3" --arg d "$FULL" \
    '{tool_name:$t,cwd:$d,tool_input:{owner:$o,repo:"widgets",title:"t",body:$b,head:"h",base:"main"}}'
}
mcp_verdict() {
  local rd=0 rr=0
  OUT_D=$(bash "$HOOK" <<<"$1" 2>&1) || rd=$?
  OUT_R=$(bash "$HOOK_DIR/run-guards.sh" block-fix-request-post.sh block-body-format-violation.sh <<<"$1" 2>&1) || rr=$?
  RCS="$rd $rr"
}
mcp_verdict "$(mcp create_pull_request "$NOFIX" acme)"
assert_eq "MCP create_pull_request, a section missing" "2 2" "$RCS"
assert_contains "MCP create_pull_request names the section" "$OUT_D" 'Missing a "## Fix" section'
mcp_verdict "$(mcp create_pull_request "$GOOD" acme)"
assert_eq "MCP create_pull_request, compliant" "0 0" "$RCS"
mcp_verdict "$(mcp update_pull_request "$NOOPEN" acme)"
assert_eq "MCP update_pull_request, no opener" "2 2" "$RCS"
mcp_verdict "$(mcp create_pull_request "$NOFIX" someone-else)"
assert_eq "MCP create_pull_request to another repository" "0 0" "$RCS"
mcp_verdict "$(mcp issue_write "$NOFIX" acme)"
assert_eq "MCP issue_write" "0 0" "$RCS"

P=$(payload "gh pr create --title t --body-file good.md" "$FULL")
t0=${EPOCHREALTIME/./}
for _ in 1 2 3 4 5 6 7 8 9 10; do bash "$HOOK" <<<"$P" >/dev/null 2>&1; done
t1=${EPOCHREALTIME/./}
ms=$(((t1 - t0) / 10000))
printf 'block-body-format-violation: %s ms per judged call (mean of 10)\n' "$ms"
if ((ms < 1000)); then ok "a judged call runs under 1 s ($ms ms)"; else bad "a judged call took $ms ms"; fi

report
