#!/usr/bin/env bash

set -uo pipefail

unset GIT_DIR GIT_WORK_TREE GIT_CONFIG CLAUDE_PLUGIN_DATA
export GIT_CONFIG_GLOBAL="${GIT_CONFIG_GLOBAL:-/dev/null}" GIT_CONFIG_NOSYSTEM=1

HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="$HOOK_DIR/pr-body-linkage-gate.sh"

PASS=0
FAIL=0
fail() {
  echo "FAIL: $*" >&2
  FAIL=$((FAIL + 1))
}
ok() {
  echo "ok: $*"
  PASS=$((PASS + 1))
}

if ! command -v jq >/dev/null 2>&1; then
  echo "SKIP: jq not on PATH -- pr-body-linkage-gate tests skipped"
  exit 0
fi

WORK="$(mktemp -d)"
UNRELATED="$(mktemp -d)"
cleanup() { rm -rf "$WORK" "$UNRELATED"; }
trap cleanup EXIT

FIXTURE_RE='\.github/actions/pr-require-checks/(check-contract|report-ci-status)([@[:space:]]|$)'
new_repo() {
  local r="$1" gated="$2"
  mkdir -p "$r/docs/conventions"
  git -C "$r" init -q 2>/dev/null
  printf "linkage_gate_uses_pattern: '%s'\n" "$FIXTURE_RE" >"$r/docs/conventions/source-control.yaml"
  case "$gated" in
  yml | yaml)
    mkdir -p "$r/.github/workflows"
    printf 'jobs:\n  ci-status:\n    steps:\n      - uses: melodic-software/ci-workflows/.github/actions/pr-require-checks/check-contract@5e18f3d6cebd6fa5e66b0941ee0f7ed6ba288d6c # v0.58.0\n' \
      >"$r/.github/workflows/ci.$gated"
    ;;
  composite)
    mkdir -p "$r/.github/workflows"
    printf 'jobs:\n  ci-status:\n    steps:\n      - uses: melodic-software/ci-workflows/.github/actions/pr-require-checks/report-ci-status@9c5bedfbfdbdfe733b9ce4cd7ca80c1574bd4cb8 # v0.76.3\n' \
      >"$r/.github/workflows/pr-require-checks.yml"
    ;;
  nostep)
    mkdir -p "$r/.github/workflows"
    printf 'jobs:\n  ci-status:\n    steps:\n      - uses: actions/checkout@v5\n' \
      >"$r/.github/workflows/ci.yml"
    ;;
  *) ;;
  esac
}

GATED="$WORK/gated"
UNGATED="$WORK/ungated"
NOSTEP="$WORK/nostep"
GATED_YAML="$WORK/gated-yaml"
OTHER="$WORK/other"
new_repo "$GATED" yml
new_repo "$UNGATED" plain
new_repo "$NOSTEP" nostep
new_repo "$GATED_YAML" yaml
GATED_COMPOSITE="$WORK/gated-composite"
new_repo "$GATED_COMPOSITE" composite
new_repo "$OTHER" yml

mk_payload() {
  jq -n --arg cwd "$1" --arg cmd "$2" \
    '{session_id:"test",cwd:$cwd,tool_name:"Bash",tool_input:{command:$cmd}}'
}

RC=0
ERR=""
run() {
  local repo="$1" cmd="$2" payload
  payload=$(mk_payload "$repo" "$cmd")
  ERR=$(cd "$UNRELATED" && printf '%s' "$payload" | bash "$HOOK" 2>&1 >/dev/null)
  RC=$?
}

assert_allow() {
  run "$2" "$3"
  if ((RC == 0)); then ok "$1"; else fail "$1: expected allow, got rc=$RC ($ERR)"; fi
}
assert_block() {
  run "$2" "$3"
  if ((RC == 2)); then ok "$1"; else fail "$1: expected block(2), got rc=$RC ($ERR)"; fi
}

gh_body() {
  printf "gh pr create --title 'T' --body '%s'" "$1"
}

SECTIONS=$'\n\n## Summary\n\nx\n\n## Fix\n\nx\n\n## Verification\n\nx\n\n## Related\n\n- x'
GOOD=$'Closes #5'"$SECTIONS"
NO_RELATED=$'Closes #5\n\n## Summary\n\nx\n\n## Fix\n\nx\n\n## Verification\n\nx'
NO_KEYWORD=$'## Summary\n\nx\n\n## Fix\n\nx\n\n## Verification\n\nx\n\n## Related\n\n- refs #9'
ISSUE_3205=$'No linked issue\n\n## Summary\n\nwhat\n\n## Verification\n\nevidence\n\n## Related\n\n- N/A'
BAD=$'Refs: #5\n\nThis does not close #5.'"$SECTIONS"

assert_allow "ungated repo: bad body allowed" "$UNGATED" "$(gh_body "$BAD")"
assert_allow "workflows present but none wires check-contract: bad body allowed" "$NOSTEP" "$(gh_body "$BAD")"
assert_allow "non-gh command allowed" "$GATED" "git commit -m 'x'"
assert_allow "gh command that is not pr create/edit allowed" "$GATED" "gh pr view 5"

set_yaml() {
  if [[ "$2" == - ]]; then rm -f "$1/docs/conventions/source-control.yaml"; else printf '%s\n' "$2" >"$1/docs/conventions/source-control.yaml"; fi
}
PATTERN_REPO="$WORK/pattern"
new_repo "$PATTERN_REPO" yml
set_yaml "$PATTERN_REPO" -
assert_allow "no linkage_gate_uses_pattern anywhere: the gate is off" "$PATTERN_REPO" "$(gh_body "$BAD")"
set_yaml "$PATTERN_REPO" "pr_open_state: ready"
assert_allow "a team YAML without the key leaves the gate off" "$PATTERN_REPO" "$(gh_body "$BAD")"
export CLAUDE_PLUGIN_OPTION_LINKAGE_GATE_USES_PATTERN="$FIXTURE_RE"
assert_block "the userConfig value alone turns the gate on" "$PATTERN_REPO" "$(gh_body "$BAD")"
set_yaml "$PATTERN_REPO" "linkage_gate_uses_pattern: 'no-such-step'"
assert_allow "the team YAML wins over the userConfig value" "$PATTERN_REPO" "$(gh_body "$BAD")"
unset CLAUDE_PLUGIN_OPTION_LINKAGE_GATE_USES_PATTERN
set_yaml "$PATTERN_REPO" "linkage_gate_uses_pattern: 'actions/checkout|pr-require-checks/check-contract@'"
assert_block "a consumer's own pattern gates its own step" "$PATTERN_REPO" "$(gh_body "$BAD")"
set_yaml "$PATTERN_REPO" "linkage_gate_uses_pattern: '(unclosed'"
assert_allow "an invalid pattern leaves the gate off" "$PATTERN_REPO" "$(gh_body "$BAD")"
if [[ "$ERR" == *"not a valid POSIX ERE"* ]]; then ok "an invalid pattern says so"; else fail "an invalid pattern gave no note: $ERR"; fi
set_yaml "$PATTERN_REPO" $'linkage_gate_uses_pattern: a\nlinkage_gate_uses_pattern: b'
export CLAUDE_PLUGIN_OPTION_LINKAGE_GATE_USES_PATTERN="$FIXTURE_RE"
assert_allow "a team YAML that does not parse stops the lookup" "$PATTERN_REPO" "$(gh_body "$BAD")"
if [[ "$ERR" == *"does not parse"* ]]; then ok "an unparsable team YAML says so"; else fail "an unparsable team YAML gave no note: $ERR"; fi
unset CLAUDE_PLUGIN_OPTION_LINKAGE_GATE_USES_PATTERN

assert_allow "compliant body allowed" "$GATED" "$(gh_body "$GOOD")"
assert_allow "missing ## Related is not blocked" "$GATED" "$(gh_body "$NO_RELATED")"
assert_allow "missing closing line is not blocked" "$GATED" "$(gh_body "$NO_KEYWORD")"
assert_allow "empty ## Related is not blocked" "$GATED" \
  "$(gh_body $'Closes #5\n\n## Summary\n\nx\n\n## Fix\n\nx\n\n## Verification\n\nx\n\n## Related\n\n## Test plan\n\n- ran it')"
assert_allow "#3205 body (no ## Fix) is not blocked" "$GATED" "$(gh_body "$ISSUE_3205")"
assert_allow "an empty literal body is not blocked" "$GATED" "gh pr create -t T --body ''"

printf '%s\n' $'Refs: #5\n\n```\nThis does not close #5.\n```'"$SECTIONS" >"$GATED/fenced-negated.md"
printf '%s\n' $'Refs: #5\n\n    This does not close #5.'"$SECTIONS" >"$GATED/indented-negated.md"
printf '%s\n' $'Refs: #5\n\n\tThis does not close #5.'"$SECTIONS" >"$GATED/tab-indented-negated.md"
assert_allow "a negated closer inside a fenced sample is masked" "$GATED" "gh pr create -t T --body-file fenced-negated.md"
assert_allow "a negated closer in indented code is masked" "$GATED" "gh pr create -t T --body-file indented-negated.md"
assert_allow "a negated closer in tab-indented code is masked" "$GATED" "gh pr create -t T --body-file tab-indented-negated.md"
assert_block "a line starting with a lowercase t is not code" "$GATED" \
  "$(gh_body $'this PR does not close #5'"$SECTIONS")"
{
  printf 'Refs: #5\n\n'
  printf 'crafted '
  t=1
  while ((t <= 80)); do
    printf '%*s' "$t" '' | tr ' ' '`'
    printf x
    t=$((t + 1))
  done
  printf '\n\nThis does not close #5.%s\n' "$SECTIONS"
} >"$GATED/superlinear-ticks.md"
start_s=$SECONDS
assert_block "a crafted unmatched-tick line does not hide a later negated closer" "$GATED" "gh pr create -t T --body-file superlinear-ticks.md"
elapsed=$((SECONDS - start_s))
if ((elapsed < 5)); then
  ok "crafted unmatched-tick line stays well under the 15s hook timeout (${elapsed}s)"
else
  fail "crafted unmatched-tick line took ${elapsed}s (must stay under 5s here)"
fi
printf '%s\n' $'Refs: #5\n\nSee the format: `` does not close #5 `x` `` for reference.'"$SECTIONS" >"$GATED/nested-ticks.md"
assert_allow "a negated closer inside nested backticks is masked" "$GATED" \
  "gh pr create -t T --body-file nested-ticks.md"
printf '%s\n' $'This does not close #5.\n\nSee the format: `` closes #9 `x` `` for reference.'"$SECTIONS" >"$GATED/nested-ticks-plus-real.md"
assert_block "a real negated closer is not hidden by nested backtick decoys" "$GATED" \
  "gh pr create -t T --body-file nested-ticks-plus-real.md"
printf '%s\n' $'Refs: #5\n\nUse `` ` `` because `does not close #5` is shown.'"$SECTIONS" >"$GATED/escaped-tick.md"
assert_allow "a negated closer after an escaped-backtick idiom is masked" "$GATED" \
  "gh pr create -t T --body-file escaped-tick.md"

run "$GATED" "$(gh_body "$BAD")"
if [[ "$ERR" == *'Negated closing reference'* && "$ERR" == *'Refs: #N'* && "$ERR" == *'is advisory'* ]]; then
  ok "block message names the negated closer, the Refs: remedy and the advisory rest"
else
  fail "block message lacks the negated closer, the Refs: remedy or the advisory note: $ERR"
fi

for kw in Closes closes Closed Fixes fix fixed Resolves resolve resolved; do
  assert_allow "keyword '$kw' accepted" "$GATED" \
    "$(gh_body "$kw #5$SECTIONS")"
done
assert_allow "colon form accepted" "$GATED" \
  "$(gh_body $'Closes: #5'"$SECTIONS")"
assert_allow "owner/repo#N form accepted" "$GATED" \
  "$(gh_body $'Closes melodic-software/standards#5'"$SECTIONS")"
assert_allow "No linked issue marker accepted" "$GATED" \
  "$(gh_body $'No linked issue'"$SECTIONS")"
assert_allow "No related issue: marker accepted" "$GATED" \
  "$(gh_body $'No related issue: drift sweep'"$SECTIONS")"

assert_allow "Refs: #N on its own line accepted" "$GATED" \
  "$(gh_body $'Refs: #1234'"$SECTIONS")"
assert_allow "Relates to: #N on its own line accepted" "$GATED" \
  "$(gh_body $'Relates to: #1234'"$SECTIONS")"
assert_allow "Refs: owner/repo#N accepted" "$GATED" \
  "$(gh_body $'Refs: melodic-software/standards#5'"$SECTIONS")"
assert_allow "Refs: marker indented three spaces accepted" "$GATED" \
  "$(gh_body $'   REFS:  #5  '"$SECTIONS")"

assert_allow "Linear closing link line accepted" "$GATED" \
  "$(gh_body $'Closes ENG-123'"$SECTIONS")"
assert_allow "Linear non-closing link line (no colon) accepted" "$GATED" \
  "$(gh_body $'Refs ENG-123'"$SECTIONS")"
assert_allow "Jira non-closing link line accepted" "$GATED" \
  "$(gh_body $'Refs: SW2-12345'"$SECTIONS")"
assert_allow "Relates to: with a tracker key accepted" "$GATED" \
  "$(gh_body $'Relates to: SW2-7'"$SECTIONS")"
assert_allow "local-markdown non-closing link line accepted" "$GATED" \
  "$(gh_body $'Refs: local-markdown:local/markdown#7'"$SECTIONS")"

assert_block "negated closer blocks" "$GATED" \
  "$(gh_body $'This does not close #5.'"$SECTIONS")"
assert_block "negated closer blocks even beside a Refs: marker" "$GATED" \
  "$(gh_body $'Refs: #5\n\nThis PR deliberately never fixes #5.'"$SECTIONS")"
assert_block "negated closer blocks even beside a real closing keyword" "$GATED" \
  "$(gh_body $'Closes #4\n\nThis is not meant to resolve #5 here.'"$SECTIONS")"
printf '%s\n' "Refs: #5"$'\n\n'"This doesn't close #5.$SECTIONS" >"$GATED/negated-apostrophe.md"
assert_block "an n't contraction negates a closer" "$GATED" \
  "gh pr create -t T --body-file negated-apostrophe.md"
printf '%s\n' "Refs: #5"$'\n\n'$'This doesn\xe2\x80\x99t close #5.'"$SECTIONS" >"$GATED/negated-typographic.md"
assert_block "a typographic-apostrophe contraction negates a closer" "$GATED" \
  "gh pr create -t T --body-file negated-typographic.md"
assert_allow "\"not only\" is affirmative" "$GATED" \
  "$(gh_body $'This not only closes #5 but more.'"$SECTIONS")"
assert_allow "a negation before the last comma does not reach the closer" "$GATED" \
  "$(gh_body $'Not a draft, closes #5'"$SECTIONS")"
assert_allow "a negation more than five words back does not reach the closer" "$GATED" \
  "$(gh_body $'Not one two three four five closes #5'"$SECTIONS")"
printf '%s\n' $'Closes #4\n\nThe template example `does not close #5` is shown.'"$SECTIONS" >"$GATED/negated-inline.md"
assert_allow "a negated closer inside inline code is masked" "$GATED" \
  "gh pr create -t T --body-file negated-inline.md"

run "$GATED" "$(gh_body $'This does not close #5. We never fix #6.\nIt does not close #5 either.'"$SECTIONS")"
if [[ "$ERR" == *'Negated closing reference ("close #5" (trigger "not"), "fix #6" (trigger "never")): GitHub still auto-closes'* &&
  "$ERR" != *'No closing line'* ]]; then
  ok "negated-closer message lists each distinct closer once with its trigger, and nothing about missing linkage"
else
  fail "negated-closer message wrong: $ERR"
fi

assert_allow "trailing word char after #N is not a match" "$GATED" \
  "$(gh_body $'Refs: #5\n\nThis does not close #12abc.'"$SECTIONS")"
assert_allow "keyword glued to a preceding word is not a match" "$GATED" \
  "$(gh_body $'Refs: #5\n\nThis does not unclose #5.'"$SECTIONS")"

assert_allow "a negated closer inside a terminated comment is stripped" "$GATED" \
  "$(gh_body $'Refs: #5\n\n<!-- This does not close #5. -->'"$SECTIONS")"
assert_allow "an unterminated comment swallows a later negated closer" "$GATED" \
  "$(gh_body $'Refs: #5\n<!-- oops\nThis does not close #5.'"$SECTIONS")"
assert_block "a negated closer beside a comment still blocks" "$GATED" \
  "$(gh_body $'This does not close #5 <!-- issue -->'"$SECTIONS")"

printf '%s\n' "$BAD" >"$GATED/body.md"
assert_block "--body-file reads the file" "$GATED" "gh pr create -t T --body-file body.md"
assert_block "cwd with a trailing newline still reads a relative --body-file" \
  "$GATED"$'\n' "gh pr create -t T --body-file body.md"
printf '%s\n' "$GOOD" >"$GATED/good.md"
assert_allow "--body-file with a compliant file allowed" "$GATED" "gh pr create -t T -F good.md"
assert_allow "--body-file naming a missing file allowed" "$GATED" "gh pr create -t T -F absent.md"

assert_block "--body-file - reads the sole heredoc" "$GATED" \
  "$(printf "gh pr create -t T --body-file - <<'EOF'\n%s\nEOF\n" "$BAD")"
assert_allow "--body-file - with a compliant heredoc allowed" "$GATED" \
  "$(printf "gh pr create -t T --body-file - <<'EOF'\n%s\nEOF\n" "$GOOD")"
assert_block "--body \$(cat <<EOF) substitution is read" "$GATED" \
  "$(printf "gh pr create -t T --body \"\$(cat <<'EOF'\n%s\nEOF\n)\"\n" "$BAD")"
assert_allow "two heredocs are undeterminable" "$GATED" \
  "$(printf "cat <<'A' >x\njunk\nA\ngh pr create -t T --body-file - <<'EOF'\n%s\nEOF\n" "$BAD")"
assert_block "an unterminated heredoc is refused by the reader" "$GATED" \
  "$(printf "gh pr create -t T --body-file - <<'EOF'\n%s\n" "$GOOD")"
if [[ "$ERR" == *'got no parse'*'unclosed here-document'* ]]; then
  ok "the refusal names the unclosed here-doc"
else
  fail "the refusal for an unterminated heredoc: [$ERR]"
fi
# shellcheck disable=SC2016  # the literal, unexpanded $BODY is the fixture under test
assert_allow "a variable body is undeterminable" "$GATED" 'gh pr create -t T --body "$BODY"'
assert_allow "--fill carries no body flag" "$GATED" "gh pr create -t T --fill"
assert_allow "interactive create carries no body flag" "$GATED" "gh pr create"
assert_block "attached short-flag value is read" "$GATED" "$(printf "gh pr create -t T -b'%s'" "$BAD")"
assert_block "--body=VALUE form is read" "$GATED" "$(printf "gh pr create -t T --body='%s'" "$BAD")"
assert_allow "a trailing --body with no value is malformed, not empty" "$GATED" "gh pr create -t T --body"
assert_allow "a trailing --body-file with no value is malformed" "$GATED" "gh pr create -t T --body-file"
assert_allow "everything after -- is positional" "$GATED" "gh pr create -t T -- --body bad"
assert_allow "a body-file naming a directory is unreadable" "$GATED" "gh pr create -t T --body-file ."

assert_allow "a label value spelled --body is not the body" "$GATED" \
  "gh pr create -t T -l --body --fill"

assert_block "gh pr edit --body is gated" "$GATED" "$(printf "gh pr edit 5 --body '%s'" "$BAD")"
assert_block "gh pr edit --body-file is gated" "$GATED" "gh pr edit 5 --body-file body.md"
assert_allow "gh pr edit changing no body allowed" "$GATED" "gh pr edit 5 --add-label ready"
assert_allow "gh pr new alias with a compliant body allowed" "$GATED" \
  "$(printf "gh pr new -t T --body '%s'" "$GOOD")"

assert_block "env-assignment wrapper is unwrapped" "$GATED" \
  "$(printf "GH_TOKEN=x gh pr create -t T --body '%s'" "$BAD")"
assert_block "env(1) wrapper is unwrapped" "$GATED" \
  "$(printf "env GH_TOKEN=x gh pr create -t T --body '%s'" "$BAD")"
assert_block "sh -c operand is re-parsed" "$GATED" \
  "$(printf "bash -c \"gh pr create -t T --body '%s'\"" "$BAD")"
assert_allow "--repo targets a repo whose gate is unknown" "$GATED" \
  "$(printf "gh pr create -R other/repo -t T --body '%s'" "$BAD")"
assert_allow "-R attached form is out of scope too" "$GATED" \
  "$(printf "gh pr create -Rother/repo -t T --body '%s'" "$BAD")"
assert_block "sudo wrapper is unwrapped" "$GATED" \
  "$(printf "sudo gh pr create -t T --body '%s'" "$BAD")"
assert_block "sudo -u root consumes its value" "$GATED" \
  "$(printf "sudo -u root gh pr create -t T --body '%s'" "$BAD")"
assert_block "sudo -uroot attaches its value" "$GATED" \
  "$(printf "sudo -uroot gh pr create -t T --body '%s'" "$BAD")"
assert_block "sudo --user=root attaches its value" "$GATED" \
  "$(printf "sudo --user=root gh pr create -t T --body '%s'" "$BAD")"
assert_block "sudo -- ends its own options" "$GATED" \
  "$(printf "sudo -- gh pr create -t T --body '%s'" "$BAD")"
assert_block "env -u VAR consumes its value" "$GATED" \
  "$(printf "env -u GH_TOKEN gh pr create -t T --body '%s'" "$BAD")"
assert_block "sudo -r role consumes its SELinux value" "$GATED" \
  "$(printf "sudo -r staff_r gh pr create -t T --body '%s'" "$BAD")"
assert_block "sudo -t type consumes its SELinux value" "$GATED" \
  "$(printf "sudo -t sysadm_t gh pr create -t T --body '%s'" "$BAD")"

assert_allow "env -C moves the directory" "$GATED" \
  "$(printf "env -C %s gh pr create -t T --body '%s'" "$UNGATED" "$BAD")"
assert_allow "env --chdir= moves the directory" "$GATED" \
  "$(printf "env --chdir=%s gh pr create -t T --body '%s'" "$UNGATED" "$BAD")"
assert_allow "sudo -D moves the directory" "$GATED" \
  "$(printf "sudo -D %s gh pr create -t T --body '%s'" "$UNGATED" "$BAD")"
assert_allow "sudo -R moves the filesystem root" "$GATED" \
  "$(printf "sudo -R %s gh pr create -t T --body '%s'" "$UNGATED" "$BAD")"

assert_block "env -S operand is re-parsed" "$GATED" \
  "$(printf "env -S \"gh pr create -t T --body '%s'\"" "$BAD")"
assert_block "env --split-string= operand is re-parsed" "$GATED" \
  "$(printf "env --split-string=\"gh pr create -t T --body '%s'\"" "$BAD")"
assert_allow "env -S carrying a compliant body allowed" "$GATED" \
  "$(printf "env -S \"gh pr create -t T --body '%s'\"" "$GOOD")"
assert_block "env -S prefix splices the trailing argv" "$GATED" \
  "$(printf "env -S 'gh pr create' -t T --body '%s'" "$BAD")"
assert_block "env --split-string= prefix splices the trailing argv" "$GATED" \
  "env --split-string='gh pr create' -t T --body-file body.md"
assert_allow "a spliced compliant body is allowed" "$GATED" \
  "$(printf "env -S 'gh pr create' -t T --body '%s'" "$GOOD")"

assert_block "command -p is an execution wrapper" "$GATED" \
  "$(printf "command -p gh pr create -t T --body '%s'" "$BAD")"
assert_allow "command -v runs nothing" "$GATED" \
  "$(printf "command -v gh pr create -t T --body '%s'" "$BAD")"

assert_block "a sudo-wrapped cd does not poison later segments" "$GATED" \
  "$(printf "sudo cd /tmp || gh pr create -t T --body '%s'" "$BAD")"
assert_block "an env-wrapped cd does not poison later segments" "$GATED" \
  "$(printf "env cd /tmp && gh pr create -t T --body '%s'" "$BAD")"
assert_allow "command cd relocates the current shell" "$GATED" \
  "$(printf "command cd %s && gh pr create -t T --body '%s'" "$UNGATED" "$BAD")"
assert_allow "builtin cd relocates the current shell" "$GATED" \
  "$(printf "builtin cd %s && gh pr create -t T --body '%s'" "$UNGATED" "$BAD")"
assert_allow "eval cd relocates the current shell" "$GATED" \
  "$(printf "eval cd %s && gh pr create -t T --body '%s'" "$UNGATED" "$BAD")"
assert_allow "command -p cd executes the builtin" "$GATED" \
  "$(printf "command -p cd %s && gh pr create -t T --body '%s'" "$UNGATED" "$BAD")"
assert_block "command -v cd only prints, so nothing moves" "$GATED" \
  "$(printf "command -v cd && gh pr create -t T --body '%s'" "$BAD")"

assert_allow "env --help runs nothing" "$GATED" \
  "$(printf "env --help gh pr create -t T --body '%s'" "$BAD")"
assert_allow "env --version runs nothing" "$GATED" \
  "$(printf "env --version gh pr create -t T --body '%s'" "$BAD")"
assert_allow "sudo -V runs nothing" "$GATED" \
  "$(printf "sudo -V gh pr create -t T --body '%s'" "$BAD")"

assert_allow "an unrecognized sudo option bails" "$GATED" \
  "$(printf "sudo --future-option x gh pr create -t T --body '%s'" "$BAD")"
assert_allow "an unrecognized sudo shorthand bails" "$GATED" \
  "$(printf "sudo -Z gh pr create -t T --body '%s'" "$BAD")"
assert_block "recognized sudo booleans are stepped over" "$GATED" \
  "$(printf "sudo -EH gh pr create -t T --body '%s'" "$BAD")"
assert_block "recognized env booleans are stepped over" "$GATED" \
  "$(printf "env -i gh pr create -t T --body '%s'" "$BAD")"
assert_block "env --block-signal takes no separate word" "$GATED" \
  "$(printf "env --block-signal gh pr create -t T --body '%s'" "$BAD")"
assert_block "env --ignore-signal=SIG is attached" "$GATED" \
  "$(printf "env --ignore-signal=TERM gh pr create -t T --body '%s'" "$BAD")"
assert_block "sudo -B is a boolean" "$GATED" \
  "$(printf "sudo -B gh pr create -t T --body '%s'" "$BAD")"

assert_block "sudo -Eu root is a cluster ending in a value" "$GATED" \
  "$(printf "sudo -Eu root gh pr create -t T --body '%s'" "$BAD")"
assert_block "sudo -Euroot attaches the clustered value" "$GATED" \
  "$(printf "sudo -Euroot gh pr create -t T --body '%s'" "$BAD")"
assert_block "env -iu VAR is a cluster ending in a value" "$GATED" \
  "$(printf "env -iu GH_TOKEN gh pr create -t T --body '%s'" "$BAD")"
assert_allow "a chdir letter inside a cluster still moves the directory" "$GATED" \
  "$(printf "env -iC %s gh pr create -t T --body '%s'" "$UNGATED" "$BAD")"

assert_allow "sudo -i is login mode" "$GATED" \
  "$(printf "sudo -i gh pr create -t T --body '%s'" "$BAD")"
assert_allow "sudo --login is login mode" "$GATED" \
  "$(printf "sudo --login gh pr create -t T --body '%s'" "$BAD")"
assert_block "sudo -s keeps the current directory" "$GATED" \
  "$(printf "sudo -s gh pr create -t T --body '%s'" "$BAD")"

for spelling in "gh.exe" "/usr/bin/gh" "./gh" "/c/Program Files/GitHub CLI/gh.exe"; do
  assert_block "'$spelling' is the same call" "$GATED" \
    "$(printf "'%s' pr create -t T --body '%s'" "$spelling" "$BAD")"
done
assert_allow "a command merely containing gh is not gh" "$GATED" \
  "npm run lighthouse-prod --body bad"

printf '%s\n' "$GOOD" >"$OTHER/bad.md"
assert_allow "cd retargets a relative --body-file" "$GATED" \
  "cd $OTHER && gh pr create -t T --body-file bad.md"
assert_allow "cd into an ungated repo is not gated" "$GATED" \
  "cd $UNGATED && $(gh_body "$BAD")"
assert_allow "pushd counts as a directory change" "$GATED" \
  "pushd $UNGATED && $(gh_body "$BAD")"
assert_allow "a cd inside sh -c still counts" "$GATED" \
  "bash -c \"cd $UNGATED && gh pr create -t T --body 'bad'\""
assert_block "a cd AFTER the gh call does not excuse it" "$GATED" \
  "$(gh_body "$BAD") && cd $UNGATED"

assert_block "-db takes the next word as the body" "$GATED" \
  "$(printf "gh pr create -db '%s'" "$BAD")"
assert_block "-dbVALUE takes the rest of the word" "$GATED" "$(printf "gh pr create -db'%s'" "$BAD")"
assert_block "-dF takes the next word as the body file" "$GATED" "gh pr create -dF body.md"
assert_block "-dFVALUE takes the rest of the word" "$GATED" "gh pr create -dFbody.md"
assert_allow "-dF with a compliant file allowed" "$GATED" "gh pr create -dF good.md"
assert_allow "-dR retargets the repo" "$GATED" \
  "$(printf "gh pr create -dR other/repo -t T --body '%s'" "$BAD")"
assert_allow "a value-taking shorthand before b consumes the body word" "$GATED" \
  "gh pr create -tb T"
assert_allow "an unknown shorthand letter is not guessed at" "$GATED" \
  "$(printf "gh pr create -zb '%s'" "$BAD")"
assert_allow "a trailing value-taking cluster has nothing to take" "$GATED" "gh pr create -t T -db"

assert_block "--body-file=X attached form" "$GATED" "gh pr create -t T --body-file=body.md"
assert_block "-FX attached form" "$GATED" "gh pr create -t T -Fbody.md"
assert_block "an absolute body-file path is read" "$GATED" "gh pr create -t T --body-file $GATED/body.md"
assert_allow "an absolute path to a compliant body allowed" "$GATED" \
  "gh pr create -t T --body-file $GATED/good.md"

printf '%s\n' "$BAD" >"$GATED_YAML/body.md"
assert_block "a .yaml gate workflow enforces too" "$GATED_YAML" "gh pr create -t T --body-file body.md"
printf '%s\n' "$BAD" >"$GATED_COMPOSITE/body.md"
assert_block "the report-ci-status composite enforces too" "$GATED_COMPOSITE" "gh pr create -t T --body-file body.md"

locale_case() {
  local label="$1" body="$2" payload utf c
  printf '%s' "$body" >"$GATED/u.md"
  payload=$(mk_payload "$GATED" "gh pr create -t T --body-file u.md")
  printf '%s' "$payload" | LC_ALL=en_US.UTF-8 bash "$HOOK" >/dev/null 2>&1
  utf=$?
  printf '%s' "$payload" | LC_ALL=C bash "$HOOK" >/dev/null 2>&1
  c=$?
  if ((utf == 2 && c == 2)); then
    ok "$label (locale-independent)"
  else
    fail "$label: utf8 rc=$utf, C rc=$c (both should block)"
  fi
}

locale_case "NBSP between keyword and issue" $'This does not close:\xc2\xa0#5.'"$SECTIONS"
locale_case "em space between keyword and issue" $'This does not close\xe2\x80\x83#5.'"$SECTIONS"

printf 'Closes #5\r\n\r\n## Summary\r\n\r\nx\r\n\r\n## Fix\r\n\r\nx\r\n\r\n## Verification\r\n\r\nx\r\n\r\n## Related\r\n\r\n- x\r\n' >"$GATED/crlf-good.md"
printf 'Refs: #5\r\n\r\nThis does not close #5.\r\n' >"$GATED/crlf-bad.md"
assert_allow "a CRLF body validates" "$GATED" "gh pr create -t T --body-file crlf-good.md"
assert_block "a CRLF body still fails when it should" "$GATED" "gh pr create -t T --body-file crlf-bad.md"

{
  printf 'Closes #5\n\n'
  dense_i=0
  while ((dense_i < 16000)); do
    printf 'aa\n'
    dense_i=$((dense_i + 1))
  done
  printf '\nThis does not close #6.\n'
} >"$GATED/dense.md"
dense_start=${EPOCHREALTIME:-}
run "$GATED" "gh pr create -t T --body-file dense.md"
dense_end=${EPOCHREALTIME:-}
if ((RC != 2)); then
  fail "16000 two-char-line body ending in a negated closer should block, got rc=$RC"
elif [[ -z "$dense_start" || -z "$dense_end" ]]; then
  echo "SKIP: EPOCHREALTIME unavailable -- dense-body timing not measured"
else
  dense_ms=$(awk -v s="${dense_start/,/.}" -v e="${dense_end/,/.}" 'BEGIN{printf "%d", (e-s)*1000}')
  if ((dense_ms < 8000)); then
    ok "16000 two-char-line body judged in ${dense_ms}ms (hooks.json timeout is 15s)"
  else
    fail "16000 two-char-line body took ${dense_ms}ms -- exceeds the 15s hook timeout"
  fi
fi

blank_run="$(printf '%20000s' '')"
printf 'Closes #5\n\n## Summary\n\nx%s\n\n## Fix\n\nx\n\n## Verification\n\nx\n\n## Related\n\n- x\n' "$blank_run" >"$GATED/blanks.md"
blanks_start=${EPOCHREALTIME:-}
run "$GATED" "gh pr create -t T --body-file blanks.md"
blanks_end=${EPOCHREALTIME:-}
if ((RC != 0)); then
  fail "compliant body with 20000 trailing blanks should allow, got rc=$RC"
elif [[ -z "$blanks_start" || -z "$blanks_end" ]]; then
  echo "SKIP: EPOCHREALTIME unavailable -- trailing-blank timing not measured"
else
  blanks_ms=$(awk -v s="${blanks_start/,/.}" -v e="${blanks_end/,/.}" 'BEGIN{printf "%d", (e-s)*1000}')
  if ((blanks_ms < 8000)); then
    ok "20000 trailing blanks judged in ${blanks_ms}ms (hooks.json timeout is 15s)"
  else
    fail "20000 trailing blanks took ${blanks_ms}ms -- exceeds the 15s hook timeout"
  fi
fi

for tmp_case in "compliant:$GOOD:0" "blocked:$BAD:2" "dense:@dense.md:2"; do
  tmp_name="${tmp_case%%:*}"
  tmp_rest="${tmp_case#*:}"
  tmp_want="${tmp_rest##*:}"
  tmp_body="${tmp_rest%:*}"
  if [[ "$tmp_body" == @* ]]; then
    tmp_cmd="gh pr create -t T --body-file ${tmp_body#@}"
  else
    tmp_cmd="$(gh_body "$tmp_body")"
  fi
  tmp_dir="$(mktemp -d "$WORK/tmp.XXXX")"
  tmp_payload=$(mk_payload "$GATED" "$tmp_cmd")
  tmp_rc=0
  (cd "$UNRELATED" && printf '%s' "$tmp_payload" | TMPDIR="$tmp_dir" bash "$HOOK" >/dev/null 2>&1) || tmp_rc=$?
  tmp_left="$(ls -A "$tmp_dir")"
  if ((tmp_rc != tmp_want)); then
    fail "$tmp_name body: expected rc=$tmp_want, got rc=$tmp_rc"
  elif [[ -n "$tmp_left" ]]; then
    fail "$tmp_name body left files in TMPDIR: $tmp_left"
  else
    ok "$tmp_name body leaves TMPDIR empty"
  fi
done

export LC_ALL=C
# shellcheck source=pr-linkage-validator.sh
source "$HOOK_DIR/pr-linkage-validator.sh"
expect_split() {
  local name="$1" text="$2"
  shift 2
  linkage::split_lines "$text"
  if ((${#LINKAGE_LINES[@]} != $#)); then
    fail "$name: expected $# elements, got ${#LINKAGE_LINES[@]}"
    return
  fi
  local i=0
  for want in "$@"; do
    if [[ "${LINKAGE_LINES[i]}" != "$want" ]]; then
      fail "$name: element $i mismatch"
      return
    fi
    i=$((i + 1))
  done
  ok "$name"
}
expect_split "empty text is one empty element" "" ""
expect_split "no trailing newline still yields the last line" $'a\nb' a b
expect_split "trailing newline yields a final empty element" $'a\nb\n' a b ""
expect_split "only a newline is two empty elements" $'\n' "" ""
split_pad="$(printf 'x%.0s' {1..16000})"
expect_split "text past the here-string limit splits the same" "$split_pad"$'\nb\n' "$split_pad" b ""

unlinked_body=$'Some prose.\n\n## Summary\ns\n\n## Fix\nf\n\n## Verification\nv\n\n## Related\nr\n'
if linkage::problems "$unlinked_body"; then
  fail "linkage::problems passed a body with no closing line"
elif [[ "${LINKAGE_PROBLEMS[*]}" == *"No closing line"* ]]; then
  ok "linkage::problems reports missing linkage on a body with every section"
else
  fail "linkage::problems did not name the missing closing line: ${LINKAGE_PROBLEMS[*]}"
fi
if linkage::problems $'Closes #5\n\n## Summary\ns\n'; then
  fail "linkage::problems passed a body missing three sections"
elif [[ "${LINKAGE_PROBLEMS[*]}" == *'Missing a "## Fix" section.'* ]]; then
  ok "linkage::problems reports a missing contract section"
else
  fail "linkage::problems did not name the missing Fix section: ${LINKAGE_PROBLEMS[*]}"
fi
if linkage::blocking_problems "$unlinked_body"; then
  ok "linkage::blocking_problems allows a body with no closing line"
else
  fail "linkage::blocking_problems blocked an advisory-only body: ${LINKAGE_PROBLEMS[*]}"
fi

{
  printf 'Closes #5\n\n'
  perf_i=0
  while ((perf_i < 1000)); do
    printf 'filler line %d with several words on it\n' "$perf_i"
    perf_i=$((perf_i + 1))
  done
  printf '\n## Summary\n\nx\n\n## Fix\n\nx\n\n## Verification\n\nx\n\n## Related\n\n- x\n'
} >"$GATED/big.md"
perf_start=${EPOCHREALTIME:-}
run "$GATED" "gh pr create -t T --body-file big.md"
perf_end=${EPOCHREALTIME:-}
if [[ -z "$perf_start" || -z "$perf_end" ]]; then
  echo "SKIP: EPOCHREALTIME unavailable -- large-body timing not measured"
elif ((RC != 0)); then
  fail "1000-line compliant body should allow, got rc=$RC"
else
  perf_ms=$(awk -v s="${perf_start/,/.}" -v e="${perf_end/,/.}" 'BEGIN{printf "%d", (e-s)*1000}')
  if ((perf_ms < 8000)); then
    ok "1000-line body judged in ${perf_ms}ms (hooks.json timeout is 15s)"
  else
    fail "1000-line body took ${perf_ms}ms -- too close to the 15s hook timeout"
  fi
fi

timed_run() {
  local label="$1" file="$2" want="$3" t0 t1 ms
  t0=${EPOCHREALTIME:-}
  run "$GATED" "gh pr create -t T --body-file $file"
  t1=${EPOCHREALTIME:-}
  if ((RC != want)); then
    fail "$label: expected rc=$want, got rc=$RC"
  elif [[ -z "$t0" || -z "$t1" ]]; then
    echo "SKIP: EPOCHREALTIME unavailable -- $label timing not measured"
  else
    ms=$(awk -v s="${t0/,/.}" -v e="${t1/,/.}" 'BEGIN{printf "%d", (e-s)*1000}')
    if ((ms < 8000)); then
      ok "$label judged in ${ms}ms (hooks.json timeout is 15s)"
    else
      fail "$label took ${ms}ms -- exceeds the 8s bound"
    fi
  fi
}

{
  yes w | head -n 30000 | tr '\n' ' '
  printf 'closes #1\n\n## Summary\n\nx\n\n## Fix\n\nx\n\n## Verification\n\nx\n\n## Related\n\n- x\n'
} >"$GATED/long-words.md"
timed_run "30000-word line ending in closes #1" long-words.md 0

{
  yes "\`w\`" | head -n 15000 | tr '\n' ' '
  printf 'closes #1\n\n## Summary\n\nx\n\n## Fix\n\nx\n\n## Verification\n\nx\n\n## Related\n\n- x\n'
} >"$GATED/long-spans.md"
timed_run "15000 inline spans on a line ending in closes #1" long-spans.md 0

{
  printf 'This does not close #5.\n<!--\n'
  printf '\n%.0s' {1..65400}
  printf 'x'
} >"$GATED/long-newlines.md"
timed_run "a negated closer, an unterminated comment, 65400 newlines and x" long-newlines.md 2

{
  printf 'This does not close #5.\n```\n'
  printf '\n%.0s' {1..65400}
  printf 'x'
} >"$GATED/long-fence.md"
timed_run "a negated closer, an unclosed fence, 65400 newlines and x" long-fence.md 2

old_chomp_to() {
  local __plv_dest="$1" __plv_s="$2"
  while [[ "$__plv_s" == *$'\n' ]]; do __plv_s="${__plv_s%$'\n'}"; done
  printf -v "$__plv_dest" '%s' "$__plv_s"
}
old_negation_trigger_to() {
  local __plv_dest="$1" tail="${2##*[.!?;,]}" lower n first i
  local -a words=()
  printf -v "$__plv_dest" '%s' ""
  tail="${tail//$'\xe2\x80\x99'/\'}"
  while [[ "$tail" =~ $_PLV_WORD_ERE ]]; do
    words+=("${BASH_REMATCH[0]}")
    tail="${tail#*"${BASH_REMATCH[0]}"}"
  done
  n=${#words[@]}
  first=0
  ((n > 5)) && first=$((n - 5))
  for ((i = first; i < n; i++)); do
    lower="${words[i],,}"
    [[ "$lower" == not ]] && ((i + 1 < n)) && [[ "${words[i + 1],,}" == only ]] && continue
    case "$lower" in
    not | never | no | without | deliberately | intentionally | *"n't")
      printf -v "$__plv_dest" '%s' "${words[i]}"
      return 0
      ;;
    *) ;;
    esac
  done
}

diff_chomp_inputs=("" $'\n' $'\n\n\n' "x" $'x\n' $'x\n\n\n' $'\nx' $'a\n\nb\n\n' $'a\r\n' $'  \n \n' $'\n\nx\n')
diff_chomp_inputs+=($'\xff\n' $'a\xff\n\n' $'\xc3\n' $'\xe2\x80\n\n\n')
printf -v diff_nl_run '%300s' ''
diff_nl_run="${diff_nl_run// /$'\n'}"
diff_chomp_inputs+=("$diff_nl_run" "x$diff_nl_run" "x${diff_nl_run}y$diff_nl_run" "$(printf 'a\n%.0s' {1..50})")
diff_chomp_bad=0
_old="" _new=""
for diff_in in "${diff_chomp_inputs[@]}"; do
  old_chomp_to _old "$diff_in"
  linkage::chomp_to _new "$diff_in"
  [[ "$_old" == "$_new" ]] || diff_chomp_bad=$((diff_chomp_bad + 1))
done
if ((diff_chomp_bad == 0)); then
  ok "chomp_to matches the old loop on ${#diff_chomp_inputs[@]} inputs, an all-newline string included"
else
  fail "chomp_to differs from the old loop on $diff_chomp_bad of ${#diff_chomp_inputs[@]} inputs"
fi
linkage::chomp_to _new $'\n\n\n'
if [[ -z "$_new" ]]; then
  ok "an all-newline input chomps to the empty string"
else
  fail "an all-newline input chomped to '$_new'"
fi

diff_neg_inputs=(
  "" "closes" "we do not " "this does not only " "not only " "We never, ever " "No. Fixes "
  "this does not close it; instead " "isn't " "it isn’t " "don't want to " "'not' " "''not "
  "a b c d e not " "not a b c d e " "not a b c d " "without any of the other words " "x-not " "n't "
  "deliberately  ,  intentionally  " "never only " "not not only " "!!! " "word1 word2 not 3 4 " "a'b'c not " "'' ' ''' "
  "Not Only the first " "the NEVER of it " "intentionally; just " "tab	not	"
  "$(printf 'w %.0s' {1..2000})" "not $(printf 'w %.0s' {1..2000})" "$(printf 'w %.0s' {1..2000})not "
  "$(printf 'w.%.0s' {1..300})not " "$(printf '%1000s' '')not "
)
diff_neg_bad=0
for diff_in in "${diff_neg_inputs[@]}"; do
  old_negation_trigger_to _old "$diff_in"
  negation_trigger_to _new "$diff_in"
  [[ "$_old" == "$_new" ]] || {
    diff_neg_bad=$((diff_neg_bad + 1))
    echo "  differs on: ${diff_in:0:60}: old='$_old' new='$_new'" >&2
  }
done
if ((diff_neg_bad == 0)); then
  ok "negation_trigger_to matches the old function on ${#diff_neg_inputs[@]} inputs"
else
  fail "negation_trigger_to differs from the old function on $diff_neg_bad of ${#diff_neg_inputs[@]} inputs"
fi

STUB="$WORK/stub-bin"
mkdir -p "$STUB"
jq_stub_ok=1
BASH_ABS="${BASH:-$(command -v bash)}"
for tool in dirname tr; do
  if tool_path="$(command -v "$tool" 2>/dev/null)" && [[ -n "$tool_path" ]]; then
    cp "$tool_path" "$STUB/" 2>/dev/null || jq_stub_ok=0
  else
    jq_stub_ok=0
  fi
done
if ((jq_stub_ok)) && [[ -x "$BASH_ABS" ]] && ! PATH="$STUB" command -v jq >/dev/null 2>&1; then
  payload=$(mk_payload "$GATED" "$(gh_body "$BAD")")
  if (printf '%s' "$payload" | PATH="$STUB" "$BASH_ABS" "$HOOK" >/dev/null 2>&1); then
    ok "a missing jq fails open"
  else
    fail "a missing jq did not fail open"
  fi
  JQ_DATA="$WORK/jq-data"
  mkdir -p "$JQ_DATA/skip-notices"
  first=$(printf '%s' "$payload" | PATH="$STUB" CLAUDE_PLUGIN_DATA="$JQ_DATA" "$BASH_ABS" "$HOOK" 2>/dev/null)
  second=$(printf '%s' "$payload" | PATH="$STUB" CLAUDE_PLUGIN_DATA="$JQ_DATA" "$BASH_ABS" "$HOOK_DIR/pr-linkage-mcp-gate.sh" 2>/dev/null)
  if [[ "$first" == *systemMessage* && -z "$second" ]]; then
    ok "one jq notice per session across the plugin's hooks"
  else
    fail "jq notice not shared across hooks: first=$first second=$second"
  fi
else
  echo "SKIP: could not build a jq-free PATH -- missing-jq fail-open not measured"
fi

payload=$(mk_payload "$GATED" "$(gh_body "$BAD")")
if (cd "$UNRELATED" &&
  CLAUDE_PLUGIN_OPTION_PR_BODY_LINKAGE_GATE_ENABLED=false bash "$HOOK" <<<"$payload" >/dev/null 2>&1); then
  ok "kill switch disables the gate"
else
  fail "kill switch did not disable the gate"
fi

echo
echo "passed: $PASS  failed: $FAIL"
((FAIL == 0)) || exit 1
