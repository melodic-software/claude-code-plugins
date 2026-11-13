#!/usr/bin/env bash
# Runs the `Require the advisory marker on each Follow-ups bullet` step body of
# .github/workflows/pr-require-checks.yml's ci-status under the shell Actions
# gives a step with no `shell:` (bash -e).
#
# AGENTS.md ("Review advisories while issue filing is paused"): every bullet
# under a pull request body's `## Follow-ups` heading starts with
# `Pre-existing (advisory):`, the marker the paused-filing sweep finds entries
# by. A follow-up that is not a review advisory goes under another heading or
# into a filed issue.
# test-scope: .github/workflows/pr-require-checks.yml
set -uo pipefail
unset GIT_DIR GIT_WORK_TREE GIT_CONFIG

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORKFLOW="$ROOT/.github/workflows/pr-require-checks.yml"

# shellcheck source=lib/test-harness.sh
. "$ROOT/scripts/lib/test-harness.sh"

TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT

NAME='Require the advisory marker on each Follow-ups bullet'
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
for line in "if: \${{ !cancelled() && github.event_name == 'pull_request' }}" \
  'PR_BODY: ${{ github.event.pull_request.body }}'; do
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

# expect <label> <want-rc> <PR_BODY> [want-out] [unwanted-out]
expect() {
  local label="$1" want_rc="$2" out rc
  out="$(PR_BODY="$3" bash -e "$TMP_ROOT/body.sh" 2>&1)" && rc=0 || rc=$?
  if [[ "$rc" -ne "$want_rc" ]]; then
    fail "$label: expected rc=$want_rc got rc=$rc out='$out'"
  elif [[ -n "${4:-}" && "$out" != *"$4"* ]]; then
    fail "$label: output lacks '$4': '$out'"
  elif [[ -n "${5:-}" && "$out" == *"$5"* ]]; then
    fail "$label: output has '$5': '$out'"
  else
    ok "$label"
  fi
}

MARK='Pre-existing (advisory):'

expect "an unmarked bullet fails" 1 "Closes #1

## Follow-ups

- Move the other three probes onto probeOutcome." "line 5"
expect "the error names the marker to add" 1 "## Follow-ups
- x" "start it with '$MARK '"
expect "the error names the other way out" 1 "## Follow-ups
- x" "move it out of '## Follow-ups'"
expect "the error quotes the bullet" 1 "## Follow-ups
- Left for the second chunk" "Left for the second chunk"
expect "every unmarked bullet is reported" 1 "## Follow-ups

- $MARK a
- b
- c" "line 5"
for bullet in '* x' '+ x' '1. x' '2) x'; do
  expect "an unmarked '${bullet%% *}' bullet fails" 1 "## Follow-ups
$bullet" "line 2"
done
expect "an 'Advisory:' bullet without the full marker fails" 1 "## Follow-ups
- Advisory: no eval covers it." "line 2"
expect "a bolded marker fails: the bullet must start with the marker" 1 "## Follow-ups
- **$MARK** x" "line 2"
expect "a bullet under a ### heading inside Follow-ups is still checked" 1 "## Follow-ups
### Later
- x" "line 3"
expect "a heading with trailing blanks still opens the section" 1 "## Follow-ups  "$'\t'"
- x" "line 2"
expect "CRLF line endings are read as LF" 1 $'Closes #1\r\n\r\n## Follow-ups\r\n\r\n- x\r\n' "line 5"
expect "a % in the bullet is escaped for the annotation" 1 "## Follow-ups
- 50% done" "50%25 done"

expect "marked bullets pass" 0 "Closes #1

## Follow-ups

- $MARK \`lib/hook-utils.sh\` already fails shfmt at base.
- $MARK two ADRs share number 0025.

🤖 Generated with [Claude Code](https://claude.com/claude-code)" "" "::error::"
# The shape publish-feedback.mjs followUpBullet writes.
expect "the address-feedback lane's bullet passes" 0 "## Follow-ups

- $MARK \`finding 100\` ([thread](https://github.com/o/r/pull/1#discussion_r1))" "" "::error::"
expect "continuation lines and nested bullets of a marked entry pass" 0 "## Follow-ups

- $MARK the first line
  runs on here,
  - and a nested point.
- $MARK second" "" "::error::"
expect "a prose line in the section passes" 0 "## Follow-ups

Owner design decisions; neither changes anything here.

- $MARK x" "" "::error::"
expect "the section ends at the next ## heading" 0 "## Follow-ups
- $MARK x

## Related
- not a follow-up" "" "::error::"
expect "the section ends at a # heading" 0 "## Follow-ups
- $MARK x
# Notes
- y" "" "::error::"
expect "a bullet in a fenced block inside the section passes" 0 "## Follow-ups
- $MARK x
\`\`\`
- y
\`\`\`" "" "::error::"
expect "a heading inside a fenced block opens no section" 0 "\`\`\`
## Follow-ups
\`\`\`
- y" "" "::error::"
expect "a heading inside a ~~~ block opens no section" 0 "~~~
## Follow-ups
~~~
- y" "" "::error::"
expect "an indented heading is not the heading" 0 "    ## Follow-ups
- y" "" "::error::"
expect "a differently named heading is not checked" 0 "## Follow-ups left open
- y" "" "::error::"
expect "bullets outside the section pass" 0 "## Fix

- y" "" "::error::"
expect "a body without the heading passes" 0 "Closes #1

## Summary

Text." "" "::error::"
expect "an empty body passes" 0 ""

test_harness::report
