#!/usr/bin/env bash
# Runs the `Fail a body line that would break the squash signature` step body
# of .github/workflows/pr-require-checks.yml's ci-status under the shell
# Actions gives a step with no `shell:` (bash -e).
#
# GitHub builds the squash commit message from the pull request body and wraps
# it. A message line that starts with a git header keyword and a space is read
# as a header when GitHub signs the commit, so the signature verifies invalid,
# the signed-commit rule refuses the push, and the merge queue removes the pull
# request as `branch_protection_failure` (#7279, #7360). The wrap the step
# models: a line of at most 72 characters is kept as written; a longer one is
# split on runs of spaces and tabs and filled greedily to 72 characters.
# test-scope: .github/workflows/pr-require-checks.yml
set -uo pipefail
unset GIT_DIR GIT_WORK_TREE GIT_CONFIG

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORKFLOW="$ROOT/.github/workflows/pr-require-checks.yml"

# shellcheck source=lib/test-harness.sh
. "$ROOT/scripts/lib/test-harness.sh"

TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT

NAME='Fail a body line that would break the squash signature'
step="$(awk -v name="      - name: $NAME" '$0 == name { on = 1; print; next }
  on && /^      - / { exit }
  on { print }' "$WORKFLOW")"
awk '/^        run: \|$/ { on = 1; next }
  on && /^          / { print substr($0, 11); next }
  on && /^[[:blank:]]*$/ { print ""; next }
  on { exit }' <<<"$step" >"$TMP_ROOT/body.sh"

if [[ ! -s "$TMP_ROOT/body.sh" ]]; then
  fail "no '$NAME' step with a run: | body in $WORKFLOW"
  test_harness::report
  exit 1
fi
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

# expect <label> <want-rc> <event> <TEXT> [want-out] [unwanted-out]
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
# 70 characters, so the keyword after it starts the second wrapped line.
PAD='aaaaaaaaa bbbbbbbbb ccccccccc ddddddddd eeeeeeeee fffffffff gggggggggg'
for key in tree parent author committer gpgsig encoding mergetag; do
  expect "'$key ' at a wrap point fails" 1 $PR "Closes #1

$PAD $key identity set in the step env." "::error::"
  expect "'$key ' at a line start fails" 1 $PR "Closes #1
$key identity set in the step env." "starts with '$key '"
done

# The #7225 body line that broke the queue's squash commit c2b54b0.
expect "the #7225 line fails at its real wrap point" 1 $PR \
  "- Scripts, the version-bump script and the tracker config copied from the trusted base before the head checkout and hash-checked before use; committer identity set in the step env." \
  "line 1"
expect "the error names the line, the keyword and the fix" 1 $PR "Closes #1

committer x" "line 3"
expect "the error says how to reword" 1 $PR "committer x" "Reword"
expect "every offending line is reported" 1 $PR "author a
ok
tree t" "line 3"

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
# GitHub wraps fenced lines like any other (no exemption), so a code-block
# line that starts with a keyword breaks the signature the same way.
expect "a code-block line starting with a keyword fails" 1 $PR '```
committer Bot <bot@example.com> 1700000000 +0000
```' "line 2"
expect "a long indented line loses its indent when wrapped and fails" 1 $PR \
  "  committer identity set in the step env, and the rest of this line runs past seventy-two"
expect "CRLF line endings are read as LF" 1 $PR $'Closes #1\r\n\r\ncommitter x\r\n' "line 3"
# Characters, not bytes: 70 characters with two-byte letters stay one line.
expect "non-ASCII text is measured in characters" 0 $PR \
  "éééééééééé éééééééééé éééééééééé éééééééééé éééééééééé ééééééé committer"
# A non-breaking space does not split words, as in GitHub's wrap.
expect "a non-breaking space is not a wrap point" 0 $PR \
  "$PAD "$'\xc2\xa0'"committer x"

# The merge group reads the squash commit's own message: its first line is the
# subject, never wrapped, and the rest is already wrapped.
expect "a merge-group message line starting with a keyword fails" 1 merge_group \
  "feat: x (#1)

committer identity set in the step env." "merge-group commit message line 3"
expect "a merge-group subject is not wrapped" 0 merge_group \
  "feat(pr-pipeline): wire aaaaaaaaaa bbbbbbbbbb cccccccccc dddddddddd ee committer x (#1)

Body."
expect "a clean merge-group message passes" 0 merge_group "feat: x (#1)

Body." "" "::error::"

test_harness::report
