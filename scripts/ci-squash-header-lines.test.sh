#!/usr/bin/env bash
# test-scope: .github/workflows/pr-require-checks.yml
set -uo pipefail
unset GIT_DIR GIT_WORK_TREE GIT_CONFIG
export GIT_CONFIG_GLOBAL="${GIT_CONFIG_GLOBAL:-/dev/null}" GIT_CONFIG_NOSYSTEM=1

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORKFLOW="$ROOT/.github/workflows/pr-require-checks.yml"

# shellcheck source=lib/test-harness.sh
. "$ROOT/scripts/lib/test-harness.sh"
# shellcheck source=lib/ci-step.sh
. "$ROOT/scripts/lib/ci-step.sh"

TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT

NAME='Fail a body line that would break the squash signature'
step="$(ci_step::read "$WORKFLOW" "$NAME" "$TMP_ROOT/body.sh")" || ci_step::abort "$WORKFLOW" "$NAME"
# shellcheck disable=SC2016 # workflow literals to match, not shell expansions
for line in "if: \${{ !cancelled() && (github.event_name == 'pull_request' || github.event_name == 'merge_group') }}" \
  'TEXT: ${{ github.event.merge_group.head_commit.message || github.event.pull_request.body }}' \
  'LC_ALL: C.UTF-8'; do
  if [[ "$step" == *"$line"* ]]; then ok "step carries '$line'"; else fail "step lost '$line'"; fi
done
if [[ "$step" == *"continue-on-error"* ]]; then
  fail "step must not continue on error: its exit code is the gate"
else
  ok "step fails the job on its exit code"
fi
order="$(grep -nE "^  ci-status:$|^      - name: ($NAME|Aggregate lane results)$" "$WORKFLOW" | cut -d: -f1 | paste -sd' ')"
read -r job_line step_line agg_line <<<"$order"
if [[ -n "${agg_line:-}" && "$job_line" -lt "$step_line" && "$step_line" -lt "$agg_line" ]]; then
  ok "step sits in ci-status before the aggregate"
else
  fail "step is not inside ci-status before the aggregate (lines: $order)"
fi

expect() {
  local label="$1" want_rc="$2" out rc
  out="$(LC_ALL=C.UTF-8 GITHUB_EVENT_NAME="$3" TEXT="$4" bash -e "$TMP_ROOT/body.sh" 2>&1)" && rc=0 || rc=$?
  if [[ "$rc" -ne "$want_rc" ]]; then
    fail "$label: expected rc=$want_rc got rc=$rc out='$out'"
  elif [[ -n "${5:-}" && "$out" != *"$5"* ]]; then
    fail "$label: output lacks '$5': '$out'"
  elif [[ -n "${6:-}" && "$out" == *"$6"* ]]; then
    fail "$label: output has '$6': '$out'"
  else
    ok "$label"
  fi
}

PR=pull_request
PAD='aaaaaaaaa bbbbbbbbb ccccccccc ddddddddd eeeeeeeee fffffffff gggggggggg'
expect "'committer ' at a wrap point fails" 1 $PR "Closes #1

$PAD committer identity set in the step env." "starts with 'committer '"
expect "'committer ' at a line start fails" 1 $PR "Closes #1
committer identity set in the step env." "starts with 'committer '"
for key in tree parent author gpgsig encoding mergetag; do
  expect "'$key ' at a wrap point passes" 0 $PR "Closes #1

$PAD $key identity set in the step env." "" "::error::"
  expect "'$key ' at a line start passes" 0 $PR "Closes #1
$key identity set in the step env." "" "::error::"
done
expect "the #8489 'author ' line passes" 0 $PR \
  "author or a listed human, not through an App. It removes \`status:" "" "::error::"
expect "the #7933 'parent ' line passes" 0 $PR \
  "parent pins \`smol-toml\` 1.8.0 and \`micromark-extension-math\` 3.1.0" "" "::error::"

expect "the #7225 line fails at its real wrap point" 1 $PR \
  "- Scripts, the version-bump script and the tracker config copied from the trusted base before the head checkout and hash-checked before use; committer identity set in the step env." \
  "line 1"
expect "the error names the line, the keyword and the fix" 1 $PR "Closes #1

committer x" "line 3"
expect "the error says how to reword" 1 $PR "committer x" "Reword"
expect "every offending line is reported" 1 $PR "committer a
ok
committer t" "line 3"

expect "a normal body passes" 0 $PR "Closes #1

## Summary

Sets the committer identity in the step env, and the author stays the PR's.
Every parent commit is kept."
expect "the word mid-line passes" 0 $PR "the committer identity is set in the step env"
expect "the word without a space after it passes" 0 $PR "committer: the bot
tree-entries.sh builds it"
expect "a capitalized word passes" 0 $PR "Committer identity set in the step env."
expect "an indented short line passes: it keeps its indent" 0 $PR "  committer identity set"
expect "an empty body passes" 0 $PR ""
expect "a word that lands mid-line after the wrap passes" 0 $PR \
  "aaaaaaaaa bbbbbbbbb ccccccccc ddddddddd eeeeeeeee ffff committer gggggggggggggggg"
expect "the keyword mid-line inside a code block passes" 0 $PR '```
git config user.name; the committer stays the bot
```'
expect "a code-block line starting with a keyword fails" 1 $PR '```
committer Bot <bot@example.com> 1700000000 +0000
```' "line 2"
expect "a long indented line loses its indent when wrapped and fails" 1 $PR \
  "  committer identity set in the step env, and the rest of this line runs past seventy-two"
expect "CRLF line endings are read as LF" 1 $PR $'Closes #1\r\n\r\ncommitter x\r\n' "line 3"
expect "non-ASCII text is measured in characters" 0 $PR \
  "éééééééééé éééééééééé éééééééééé éééééééééé éééééééééé ééééééé committer"
expect "a non-breaking space is not a wrap point" 0 $PR \
  "$PAD "$'\xc2\xa0'"committer x"

expect "a merge-group message line starting with a keyword fails" 1 merge_group \
  "feat: x (#1)

committer identity set in the step env." "merge-group commit message line 3"
expect "a merge-group subject is not wrapped" 0 merge_group \
  "feat(pr-pipeline): wire aaaaaaaaaa bbbbbbbbbb cccccccccc dddddddddd ee committer x (#1)

Body."
expect "a clean merge-group message passes" 0 merge_group "feat: x (#1)

Body." "" "::error::"

test_harness::report
