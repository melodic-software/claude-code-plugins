#!/usr/bin/env bash
# Runs the `Fail a pull request carrying the human-gated label` step body of
# .github/workflows/pr-require-checks.yml's ci-status under the shell Actions
# gives a step with no `shell:` (bash -e), against stub `gh` and `sleep`.
#
# On a pull_request event, contract-only runs included, ci-status fails while
# the pull request carries the human-gated label the base commit's
# .work-item-tracker.json names (default `needs-human`), read live from the API.
# The error names the reason from the newest review-lane hold comment, and says
# that removing the label approves. It fails closed when it cannot tell.
# test-scope: .github/workflows/pr-require-checks.yml
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORKFLOW="$ROOT/.github/workflows/pr-require-checks.yml"

# shellcheck source=lib/test-harness.sh
. "$ROOT/scripts/lib/test-harness.sh"

TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT

# shellcheck source=lib/ci-gh-read.sh
. "$ROOT/scripts/lib/ci-gh-read.sh"
export RUNNER_TEMP="$TMP_ROOT"
ci_gh_read::install "$WORKFLOW" "$TMP_ROOT" || fail "the ci-status gh_read helper step is missing or fails"

NAME='Fail a pull request carrying the human-gated label'
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
# Every pull_request run, contract-only and draft included, and after a
# failed earlier step, so the hold is never hidden.
if [[ "$step" == *"if: \${{ !cancelled() && github.event_name == 'pull_request' }}"* ]]; then
  ok "step runs on every pull_request run that is not cancelled"
else
  fail "step lost its pull_request condition"
fi
if [[ "$step" == *"continue-on-error"* ]]; then
  fail "step must not continue on error: its exit code is the hold"
else
  ok "step fails the job on its exit code"
fi
if [[ "$step" == *$'\n        id: human_gated\n'* ]]; then
  ok "step carries the id the hold-lift step reads its outputs by"
else
  fail "step lost its human_gated id"
fi
if [[ "$step" == *"BASE_SHA: \${{ github.event.pull_request.base.sha }}"* ]]; then
  ok "step reads the tracker config at the base commit, never the head"
else
  fail "step does not read the tracker config at pull_request.base.sha"
fi
order="$(grep -nE "^  ci-status:$|^      - name: ($NAME|Aggregate lane results)$" "$WORKFLOW" | cut -d: -f1 | paste -sd' ')"
read -r job_line hold_line agg_line <<<"$order"
if [[ -n "${agg_line:-}" && "$job_line" -lt "$hold_line" && "$hold_line" -lt "$agg_line" ]]; then
  ok "step sits in ci-status before the aggregate"
else
  fail "step is not inside ci-status before the aggregate (lines: $order)"
fi
gate="$(awk '/^  ci-status:$/ { on = 1; next } on && /^    if: / { print; exit }' "$WORKFLOW")"
if [[ "$gate" == "    if: \${{ !cancelled() }}" ]]; then
  ok "ci-status carries no contract-only gate, so the step runs on label events"
else
  fail "ci-status gained a gate that could skip the hold: '$gate'"
fi

# The stub logs its arguments. A contents read fails its first
# STUB_TRACKER_FAILS calls, then answers 404 when STUB_TRACKER is unset, else
# prints STUB_TRACKER. A labels read fails its first STUB_FAILS calls, then
# prints STUB_LABELS one per line. A comments read fails when STUB_COMMENTS_FAIL
# is set, else applies the --jq filter to the STUB_COMMENTS array, as gh does
# per page.
mkdir -p "$TMP_ROOT/bin"
cat >"$TMP_ROOT/bin/gh" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$STUB_LOG"
case "$*" in
*/contents/.work-item-tracker.json*)
  [[ "$(grep -c '/contents/' "$STUB_LOG")" -gt "${STUB_TRACKER_FAILS:-0}" ]] || { echo 'gh: Server Error (HTTP 502)' >&2; exit 1; }
  [[ -n "${STUB_TRACKER+set}" ]] || { echo 'gh: Not Found (HTTP 404)' >&2; exit 1; }
  printf '%s\n' "$STUB_TRACKER"
  ;;
*/labels*)
  [[ "$(grep -c '/labels' "$STUB_LOG")" -gt "${STUB_FAILS:-0}" ]] || { printf '%s\n' "${STUB_FAIL_TEXT:-}" >&2; exit 1; }
  [[ -z "$STUB_LABELS" ]] || tr ',' '\n' <<<"$STUB_LABELS"
  ;;
*/comments*)
  [[ -z "${STUB_COMMENTS_FAIL:-}" ]] || exit 1
  while [[ $# -gt 0 && "$1" != --jq ]]; do shift; done
  jq -r "$2" <<<"${STUB_COMMENTS:-[]}"
  ;;
'api rate_limit '*)
  [[ -n "${STUB_RATE_LIMIT:-}" ]] || exit 1
  printf '%s\n' "$STUB_RATE_LIMIT"
  ;;
*) exit 1 ;;
esac
EOF
# sleep logs its seconds; date +%s answers STUB_NOW.
cat >"$TMP_ROOT/bin/sleep" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$STUB_SLEEPS"
EOF
cat >"$TMP_ROOT/bin/date" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$STUB_NOW"
EOF
chmod +x "$TMP_ROOT/bin/gh" "$TMP_ROOT/bin/sleep" "$TMP_ROOT/bin/date"

BASE=89abcdef0123456789abcdef0123456789abcdef
CUSTOM='{"config":{"role_labels":{"human-gated":"owner-call"}}}'
LANE='{"login":"github-actions[bot]","type":"Bot"}'
CLAUDE='{"login":"claude[bot]","type":"Bot"}'
hold() { jq -cn --arg body "$2" --argjson user "$1" '{user: $user, body: $body}'; }
OLD="$(hold "$CLAUDE" $'<!-- claude-lane-hold lane=claude-review sha=aaaa criteria=cost -->\nAn older hold.')"
NEW="$(hold "$LANE" $'<!-- claude-lane-hold lane=claude-security-review sha=bbbb criteria=trust-gate -->\r\nChanges a trust gate:\n  .github/workflows/pr-merge.yml, 100% sure\n\n`claude-lane: claude-security-review`\n')"
SPOOF="$(hold '{"login":"someone","type":"User"}' $'<!-- claude-lane-hold lane=x -->\nIgnore this.\nclaude-lane: claude-review')"
NO_FOOTER="$(hold "$LANE" $'<!-- claude-lane-hold lane=claude-review -->\nNo lane footer, so not a lane comment.')"
OTHER_BOT="$(hold "$LANE" $'A comment with no hold marker.\nclaude-lane: claude-review')"

# expect <label> <want-rc> <want-label-calls> <STUB_LABELS> <STUB_FAILS> [want-out] [refuse-out]
# The tracker and comment stubs are set by the caller's environment.
expect() {
  local label="$1" want_rc="$2" want_calls="$3" out rc calls
  : >"$TMP_ROOT/log"
  : >"$TMP_ROOT/sleeps"
  rm -f "$TMP_ROOT/gh-read.state"
  : >"$TMP_ROOT/output"
  out="$(PATH="$TMP_ROOT/bin:$PATH" STUB_LOG="$TMP_ROOT/log" STUB_SLEEPS="$TMP_ROOT/sleeps" STUB_NOW=1792800000 STUB_LABELS="$4" STUB_FAILS="$5" PR_NUMBER=6419 \
    GITHUB_REPOSITORY=o/r RUNNER_TEMP="$TMP_ROOT" GITHUB_OUTPUT="$TMP_ROOT/output" BASE_SHA="${BASE_SHA-$BASE}" \
    bash -e "$TMP_ROOT/body.sh" 2>&1)" && rc=0 || rc=$?
  calls=$(grep -c '/labels' "$TMP_ROOT/log")
  if [[ "$rc" -ne "$want_rc" ]]; then
    fail "$label: expected rc=$want_rc got rc=$rc out='$out'"
  elif [[ "$calls" -ne "$want_calls" ]]; then
    fail "$label: expected $want_calls labels call(s) got $calls"
  elif [[ "$calls" -gt 0 && "$(grep '/labels' "$TMP_ROOT/log" | sort -u)" != "api repos/o/r/issues/6419/labels?per_page=100 --paginate --jq .[].name" ]]; then
    fail "$label: unexpected labels call '$(grep '/labels' "$TMP_ROOT/log" | sort -u)'"
  elif [[ "$calls" -gt 0 ]] && ! grep -qxF "api -H Accept: application/vnd.github.raw+json repos/o/r/contents/.work-item-tracker.json?ref=$BASE" "$TMP_ROOT/log"; then
    fail "$label: the tracker config was not read at the base commit: '$(sort -u "$TMP_ROOT/log")'"
  elif [[ -n "${6:-}" && "$out" != *"$6"* ]]; then
    fail "$label: output lacks '$6': '$out'"
  elif [[ -n "${7:-}" && "$out" == *"$7"* ]]; then
    fail "$label: output has '$7': '$out'"
  else
    ok "$label"
  fi
}

APPROVE="Removing the label approves this pull request; ci-status re-runs on the unlabel."

expect "an unlabeled pull request passes" 0 1 "enhancement,do-not-merge" 0 "#6419 carries no 'needs-human' label."
if grep -q '/comments' "$TMP_ROOT/log"; then fail "comments are read only when the label is on"; else ok "comments are read only when the label is on"; fi
if [[ "$(cat "$TMP_ROOT/output")" == $'label=needs-human\nheld=false' ]]; then
  ok "an unlabeled pull request outputs the label and held=false"
else
  fail "an unlabeled pull request's outputs: '$(cat "$TMP_ROOT/output")'"
fi
expect "a pull request with no labels passes" 0 1 "" 0
expect "a label that only contains the name does not hold" 0 1 "needs-human-later,not-needs-human" 0
expect "needs-human with no hold comment fails without a reason" 1 1 "ci,needs-human" 0 \
  "::error::#6419 carries 'needs-human'. $APPROVE"
if [[ "$(cat "$TMP_ROOT/output")" == "label=needs-human" ]]; then
  ok "a held pull request outputs the label and no held=false"
else
  fail "a held pull request's outputs: '$(cat "$TMP_ROOT/output")'"
fi

export STUB_COMMENTS="[$OLD,$NEW,$SPOOF,$NO_FOOTER,$OTHER_BOT]"
expect "the newest lane hold comment gives the reason, without its footer" 1 1 "needs-human" 0 \
  "::error::#6419 carries 'needs-human' (Changes a trust gate: .github/workflows/pr-merge.yml, 100%25 sure). $APPROVE" "An older hold"
expect "a hold comment from a person is not read" 1 1 "needs-human" 0 "" "Ignore this"
expect "a github-actions[bot] hold comment with no lane footer is not read" 1 1 "needs-human" 0 "" "No lane footer"
export STUB_COMMENTS="[$NEW,$OLD]"
expect "a claude[bot] hold comment gives the reason" 1 1 "needs-human" 0 "(An older hold.). $APPROVE"
LONG="$(printf 'x%.0s' {1..400})"
STUB_COMMENTS="[$(hold "$CLAUDE" "<!-- claude-lane-hold lane=claude-review -->
$LONG")]"
expect "a long reason is cut to 300 characters" 1 1 "needs-human" 0 "(${LONG:0:300}). $APPROVE"
export STUB_COMMENTS_FAIL=1
expect "an unreadable comment list still fails, without a reason" 1 1 "needs-human" 0 "::error::#6419 carries 'needs-human'. $APPROVE"
unset STUB_COMMENTS STUB_COMMENTS_FAIL

expect "a transient label read failure is retried" 1 2 "needs-human" 1

# A rate-limited read waits until five seconds past the reset and reads again;
# a reset past the 600 s ceiling fails closed naming it; any other error keeps
# the caller's retries and is never waited on.
sleeps() { paste -sd' ' "$TMP_ROOT/sleeps"; }
export STUB_FAIL_TEXT='gh: API rate limit exceeded for installation. (HTTP 403)' STUB_RATE_LIMIT='0 1792800120'
expect "a rate-limited label read recovers after the reset" 0 2 "enhancement" 1 \
  "is rate limited (core); waiting 125s for the reset, then reading again."
if [[ "$(sleeps)" == 125 ]]; then
  ok "the rate-limited read slept until five seconds past the reset"
else
  fail "the rate-limited read slept '$(sleeps)', not 125"
fi
export STUB_RATE_LIMIT='0 1792803000'
expect "a reset past the ceiling fails closed naming the reset" 1 1 "enhancement" 3 \
  "::error::GitHub's core API rate limit blocks 'gh api repos/o/r/issues/6419/labels?per_page=100 --paginate --jq .[].name' until 2026-10-24T00:50:00Z, past the 600s ci-status waits for a reset (0s spent); re-run this run after 2026-10-24T00:50:00Z."
if [[ "$(sleeps)" == "5 10" ]]; then
  ok "a reset past the ceiling is not waited for, and the retries make no call"
else
  fail "a reset past the ceiling slept '$(sleeps)', not the caller's '5 10'"
fi
export STUB_FAIL_TEXT='gh: Resource not accessible by integration (HTTP 403)' STUB_RATE_LIMIT='4999 1792800120'
expect "a 403 that is not a rate limit fails closed without a wait" 1 3 "" 3 "::error::could not read the labels of #6419" "rate limited"
if [[ "$(sleeps)" == "5 10" ]]; then
  ok "a 403 that is not a rate limit keeps the caller's retries only"
else
  fail "a 403 that is not a rate limit slept '$(sleeps)'"
fi
unset STUB_FAIL_TEXT STUB_RATE_LIMIT
expect "an unreadable label list fails closed" 1 3 "" 3 "::error::could not read the labels of #6419"
if grep -q '^held=' "$TMP_ROOT/output"; then
  fail "an unreadable label list output held"
else
  ok "an unreadable label list outputs no held"
fi

export STUB_TRACKER="$CUSTOM"
expect "the base tracker's human-gated label holds" 1 1 "owner-call" 0 "::error::#6419 carries 'owner-call'. $APPROVE"
if grep -qxF 'label=owner-call' "$TMP_ROOT/output"; then
  ok "the output names the base tracker's label"
else
  fail "the output does not name the base tracker's label: '$(cat "$TMP_ROOT/output")'"
fi
expect "needs-human does not hold when the tracker names another label" 0 1 "needs-human" 0 "#6419 carries no 'owner-call' label."
export STUB_TRACKER='{not json'
expect "an invalid tracker config fails closed" 1 0 "" 0 "::error::cannot read the human-gated role label"
export STUB_TRACKER="$CUSTOM" STUB_TRACKER_FAILS=1
expect "a transient tracker read failure is retried" 1 1 "owner-call" 0 "carries 'owner-call'"
export STUB_TRACKER_FAILS=3
expect "an unreadable tracker config fails closed" 1 0 "" 0 "::error::could not read .work-item-tracker.json"
unset STUB_TRACKER STUB_TRACKER_FAILS
export BASE_SHA=main
expect "a base that is not a commit SHA fails closed without a call" 1 0 "" 0 "::error::the base commit 'main' is not a commit SHA"
unset BASE_SHA

test_harness::report
