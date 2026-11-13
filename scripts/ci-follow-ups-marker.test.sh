#!/usr/bin/env bash
# Runs the `Require the advisory marker on each Follow-ups bullet` step body of
# .github/workflows/pr-require-checks.yml's ci-status under the shell Actions
# gives a step with no `shell:` (bash -e).
#
# AGENTS.md ("Review advisories while issue filing is paused"): every bullet
# under a pull request body's `## Follow-ups` heading starts with
# `Pre-existing (advisory):`, the marker the paused-filing sweep finds entries
# by. A follow-up that is not a review advisory goes under another heading or
# into a filed issue. The step reports and exits 0 unless its
# FAIL_ON_UNMARKED_FOLLOW_UPS switch is 'true'.
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
  'PR_BODY: ${{ github.event.pull_request.body }}' \
  "FAIL_ON_UNMARKED_FOLLOW_UPS: 'false'"; do
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
# BLOCKING is the FAIL_ON_UNMARKED_FOLLOW_UPS value, the step's 'false' unless
# a case sets it. The step summary is kept in $SUMMARY.
BLOCKING=false
SUMMARY="$TMP_ROOT/summary.md"
expect() {
  local label="$1" want_rc="$2" out rc
  : >"$SUMMARY"
  out="$(PR_BODY="$3" FAIL_ON_UNMARKED_FOLLOW_UPS="$BLOCKING" GITHUB_STEP_SUMMARY="$SUMMARY" \
    bash -e "$TMP_ROOT/body.sh" 2>&1)" && rc=0 || rc=$?
  out_last=$out
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

expect "an unmarked bullet is reported" 0 "Closes #1

## Follow-ups

- Move the other three probes onto probeOutcome." "line 5"
expect "the warning names the marker to add" 0 "## Follow-ups
- x" "start it with '$MARK '"
expect "the warning names the other way out" 0 "## Follow-ups
- x" "move it out of '## Follow-ups'"
expect "the warning quotes the bullet" 0 "## Follow-ups
- Left for the second chunk" "Left for the second chunk"
expect "every unmarked bullet is reported" 0 "## Follow-ups

- $MARK a
- b
- c" "line 5"
for bullet in '* x' '+ x' '1. x' '2) x'; do
  expect "an unmarked '${bullet%% *}' bullet is reported" 0 "## Follow-ups
$bullet" "line 2"
done
expect "an 'Advisory:' bullet without the full marker is reported" 0 "## Follow-ups
- Advisory: no eval covers it." "line 2"
expect "a bolded marker is reported: the bullet must start with the marker" 0 "## Follow-ups
- **$MARK** x" "line 2"
expect "a bullet under a ### heading inside Follow-ups is still checked" 0 "## Follow-ups
### Later
- x" "line 3"
expect "a heading with trailing blanks still opens the section" 0 "## Follow-ups  "$'\t'"
- x" "line 2"
expect "CRLF line endings are read as LF" 0 $'Closes #1\r\n\r\n## Follow-ups\r\n\r\n- x\r\n' "line 5"
# CommonMark: up to three leading spaces is still a top-level item.
expect "a top-level bullet indented two spaces is reported" 0 "## Follow-ups

  - Unmarked advisory" "line 3"
expect "a top-level bullet indented three spaces is reported" 0 "## Follow-ups
   * x" "line 2"
expect "an indented bullet after a narrower-content item is top level" 0 "## Follow-ups
- $MARK a
 - b" "line 3"
expect "after prose ends the list, an indented bullet is top level again" 0 "## Follow-ups
- $MARK a

Some prose.

  - b" "line 6"
expect "a lazy continuation keeps the list, so its nested bullet is skipped" 0 "## Follow-ups
- $MARK a
lazy continuation
  - nested" "" "::warning::"
expect "a nested bullet under a marked item is skipped" 0 "## Follow-ups

- $MARK a

  - nested point" "" "::warning::"
expect "a nested item under a numbered entry is skipped" 0 "## Follow-ups
1. $MARK a
   - nested" "" "::warning::"
expect "a bullet indented four spaces with no item above is not an item" 0 "## Follow-ups

    - code, not a list" "" "::warning::"
expect "a % in the bullet is escaped for the annotation" 0 "## Follow-ups
- 50% done" "50%25 done"
expect "report-only: a finding is a warning, not an error" 0 "## Follow-ups
- x" "::warning::For a review advisory, start it with" "::error::"
expect "a warning per unmarked bullet" 0 "## Follow-ups
- a
- b" "line 3"
if [[ "$(grep -c '^::warning::' <<<"$out_last")" -eq 2 ]]; then
  ok "two unmarked bullets give two warnings"
else
  fail "two unmarked bullets did not give two warnings: '$out_last'"
fi
if grep -qF '### 2 bullet(s) under' "$SUMMARY" && grep -qF '| 2 | a |' "$SUMMARY" &&
  grep -qF '| 3 | b |' "$SUMMARY" && grep -qF "start the bullet with \`$MARK\`" "$SUMMARY"; then
  ok "the step summary lists each bullet and names the fix"
else
  fail "the step summary lacks the findings: '$(cat "$SUMMARY")'"
fi
expect "a | in a bullet is escaped in the summary table" 0 "## Follow-ups
- a | b"
if grep -qF '| 2 | a \| b |' "$SUMMARY"; then ok "summary escapes |"; else fail "summary: '$(cat "$SUMMARY")'"; fi
expect "a clean body writes no summary" 0 "## Follow-ups
- $MARK x"
if [[ ! -s "$SUMMARY" ]]; then ok "no summary for a clean body"; else fail "summary written: '$(cat "$SUMMARY")'"; fi

BLOCKING=true
expect "with the blocking switch on, an unmarked bullet fails" 1 "## Follow-ups
- x" "::error::For a review advisory, start it with" "::warning::"
expect "with the blocking switch on, a marked body passes" 0 "## Follow-ups
- $MARK x" "" "::error::"
BLOCKING=false

expect "marked bullets pass" 0 "Closes #1

## Follow-ups

- $MARK \`lib/hook-utils.sh\` already fails shfmt at base.
- $MARK two ADRs share number 0025.

🤖 Generated with [Claude Code](https://claude.com/claude-code)" "" "::warning::"
# The shape publish-feedback.mjs followUpBullet writes.
expect "the address-feedback lane's bullet passes" 0 "## Follow-ups

- $MARK \`finding 100\` ([thread](https://github.com/o/r/pull/1#discussion_r1))" "" "::warning::"
expect "continuation lines and nested bullets of a marked entry pass" 0 "## Follow-ups

- $MARK the first line
  runs on here,
  - and a nested point.
- $MARK second" "" "::warning::"
expect "a prose line in the section passes" 0 "## Follow-ups

Owner design decisions; neither changes anything here.

- $MARK x" "" "::warning::"
expect "the section ends at the next ## heading" 0 "## Follow-ups
- $MARK x

## Related
- not a follow-up" "" "::warning::"
expect "the section ends at a # heading" 0 "## Follow-ups
- $MARK x
# Notes
- y" "" "::warning::"
expect "a bullet in a fenced block inside the section passes" 0 "## Follow-ups
- $MARK x
\`\`\`
- y
\`\`\`" "" "::warning::"
expect "a heading inside a fenced block opens no section" 0 "\`\`\`
## Follow-ups
\`\`\`
- y" "" "::warning::"
expect "a heading inside a ~~~ block opens no section" 0 "~~~
## Follow-ups
~~~
- y" "" "::warning::"
expect "an indented heading is not the heading" 0 "    ## Follow-ups
- y" "" "::warning::"
expect "a differently named heading is not checked" 0 "## Follow-ups left open
- y" "" "::warning::"
expect "bullets outside the section pass" 0 "## Fix

- y" "" "::warning::"
expect "a body without the heading passes" 0 "Closes #1

## Summary

Text." "" "::warning::"
expect "an empty body passes" 0 ""

test_harness::report
