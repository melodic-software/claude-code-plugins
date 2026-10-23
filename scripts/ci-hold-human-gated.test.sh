#!/usr/bin/env bash
# Runs the `Fail a pull request carrying the human-gated label` step body of
# .github/workflows/pr-require-checks.yml's ci-status under the shell Actions
# gives a step with no `shell:` (bash -e), against stub `gh` and `sleep`.
#
# On a pull_request event, contract-only runs included, ci-status fails while
# the pull request carries the human-gated label the base commit's
# .work-item-tracker.json names (default `needs-human`), read from the base
# commit's sparse checkout; the labels are read live from the API.
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
if [[ "$step" == *"BASE_CONFIG: \${{ steps.base_config.outcome == 'success' && format('{0}/base-config', github.workspace) || '' }}"* ]]; then
  ok "step reads the tracker config from the base checkout, and none when it failed"
else
  fail "step does not read the tracker config from the base_config checkout"
fi
order="$(grep -nE "^  ci-status:$|^      - name: ($NAME|Aggregate lane results)$" "$WORKFLOW" | cut -d: -f1 | paste -sd' ')"
read -r job_line hold_line agg_line <<<"$order"
if [[ -n "${agg_line:-}" && "$job_line" -lt "$hold_line" && "$hold_line" -lt "$agg_line" ]]; then
  ok "step sits in ci-status before the aggregate"
else
  fail "step is not inside ci-status before the aggregate (lines: $order)"
fi
# The config comes from a sparse checkout of the base commit: never the head,
# never a persisted credential, and before every step that reads it.
checkout="$(awk '$0 == "      - name: Check out the base commit'"'"'s hold config" { on = 1; print; next }
  on && /^      - / { exit }
  on { print }' "$WORKFLOW")"
# shellcheck disable=SC2016 # workflow literals to match, not shell expansions
for line in $'\n        id: base_config\n' 'continue-on-error: true' \
  'ref: ${{ github.event.pull_request.base.sha || github.event.merge_group.base_sha }}' \
  'persist-credentials: false' '/.work-item-tracker.json' '/.github/standards/trusted-actors/trusted-actors.json' \
  'sparse-checkout-cone-mode: false' 'path: base-config'; do
  if [[ "$checkout" == *"$line"* ]]; then ok "the base checkout carries '${line//$'\n'/}'"; else fail "the base checkout lost '${line//$'\n'/}'"; fi
done
order="$(grep -nE "^  ci-status:$|^      - name: (Check out the base commit's hold config|Clear a cost-only review hold the owner decided)$" "$WORKFLOW" | cut -d: -f1 | paste -sd' ')"
read -r job_line checkout_line cost_line <<<"$order"
if [[ -n "${cost_line:-}" && "$job_line" -lt "$checkout_line" && "$checkout_line" -lt "$cost_line" ]]; then
  ok "the base checkout sits in ci-status before the first step that reads it"
else
  fail "the base checkout is not in ci-status before the cost-hold step (lines: $order)"
fi
gate="$(awk '/^  ci-status:$/ { on = 1; next } on && /^    if: / { print; exit }' "$WORKFLOW")"
if [[ "$gate" == "    if: \${{ !cancelled() }}" ]]; then
  ok "ci-status carries no contract-only gate, so the step runs on label events"
else
  fail "ci-status gained a gate that could skip the hold: '$gate'"
fi

# The base commit's config is a fixture directory: STUB_TRACKER is its
# .work-item-tracker.json (absent when unset), and STUB_CHECKOUT_FAILED leaves
# BASE_CONFIG empty, as a failed checkout does. The gh stub logs its
# arguments. A labels read fails its first STUB_FAILS calls, then
# prints STUB_LABELS one per line. A comments read fails when STUB_COMMENTS_FAIL
# is set, else applies the --jq filter to the STUB_COMMENTS array, as gh does
# per page.
mkdir -p "$TMP_ROOT/bin"
cat >"$TMP_ROOT/bin/gh" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$STUB_LOG"
case "$*" in
*/labels*)
  [[ "$(grep -c '/labels' "$STUB_LOG")" -gt "${STUB_FAILS:-0}" ]] || exit 1
  [[ -z "$STUB_LABELS" ]] || tr ',' '\n' <<<"$STUB_LABELS"
  ;;
*/comments*)
  [[ -z "${STUB_COMMENTS_FAIL:-}" ]] || exit 1
  while [[ $# -gt 0 && "$1" != --jq ]]; do shift; done
  jq -r "$2" <<<"${STUB_COMMENTS:-[]}"
  ;;
*) exit 1 ;;
esac
EOF
printf '#!/usr/bin/env bash\n' >"$TMP_ROOT/bin/sleep"
chmod +x "$TMP_ROOT/bin/gh" "$TMP_ROOT/bin/sleep"

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
  : >"$TMP_ROOT/output"
  rm -rf "$TMP_ROOT/base-config"
  mkdir -p "$TMP_ROOT/base-config"
  [[ -z "${STUB_TRACKER+set}" ]] || printf '%s\n' "$STUB_TRACKER" >"$TMP_ROOT/base-config/.work-item-tracker.json"
  local config="$TMP_ROOT/base-config"
  [[ -z "${STUB_CHECKOUT_FAILED:-}" ]] || config=
  out="$(PATH="$TMP_ROOT/bin:$PATH" STUB_LOG="$TMP_ROOT/log" STUB_LABELS="$4" STUB_FAILS="$5" PR_NUMBER=6419 \
    GITHUB_REPOSITORY=o/r RUNNER_TEMP="$TMP_ROOT" GITHUB_OUTPUT="$TMP_ROOT/output" BASE_SHA="${BASE_SHA-$BASE}" \
    BASE_CONFIG="$config" bash -e "$TMP_ROOT/body.sh" 2>&1)" && rc=0 || rc=$?
  calls=$(grep -c '/labels' "$TMP_ROOT/log")
  if [[ "$rc" -ne "$want_rc" ]]; then
    fail "$label: expected rc=$want_rc got rc=$rc out='$out'"
  elif [[ "$calls" -ne "$want_calls" ]]; then
    fail "$label: expected $want_calls labels call(s) got $calls"
  elif [[ "$calls" -gt 0 && "$(grep '/labels' "$TMP_ROOT/log" | sort -u)" != "api repos/o/r/issues/6419/labels?per_page=100 --paginate --jq .[].name" ]]; then
    fail "$label: unexpected labels call '$(grep '/labels' "$TMP_ROOT/log" | sort -u)'"
  elif grep -q '/contents/' "$TMP_ROOT/log"; then
    fail "$label: the tracker config was read through the API: '$(sort -u "$TMP_ROOT/log")'"
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
export STUB_TRACKER="$CUSTOM" STUB_CHECKOUT_FAILED=1
expect "a base checkout that failed fails closed" 1 0 "" 0 "::error::could not read .work-item-tracker.json at $BASE; re-run this run."
unset STUB_TRACKER STUB_CHECKOUT_FAILED
export STUB_TRACKER=''
expect "an empty tracker config falls back to needs-human" 1 1 "needs-human" 0 "carries 'needs-human'"
unset STUB_TRACKER
export BASE_SHA=main
expect "a base that is not a commit SHA fails closed without a call" 1 0 "" 0 "::error::the base commit 'main' is not a commit SHA"
unset BASE_SHA

test_harness::report
