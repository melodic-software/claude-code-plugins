#!/usr/bin/env bash
# Runs the `Clear a cost-only review hold the owner decided` step body of
# .github/workflows/pr-require-checks.yml's ci-status under the shell Actions
# gives a step with no `shell:` (bash -e), against stub `gh` and `sleep`.
#
# A review lane's `cost` hold is cleared when every lane hold since a trusted
# person last removed the human-gated label is cost-only, and the pull request
# body cites the owner's unedited `**Decision recorded.** Cost:` comment on its
# closing issue (newer than the pull request) or on the pull request itself.
# The step then outputs cleared=true and the decision, and takes the label off
# with one comment citing it. Anything else, an unreadable read included,
# clears nothing and leaves the hold to the steps after it.
# test-scope: .github/workflows/pr-require-checks.yml
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORKFLOW="$ROOT/.github/workflows/pr-require-checks.yml"

# shellcheck source=lib/test-harness.sh
. "$ROOT/scripts/lib/test-harness.sh"

TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT

NAME='Clear a cost-only review hold the owner decided'
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
if [[ "$step" == *"if: \${{ !cancelled() && github.event_name == 'pull_request' }}"* ]]; then
  ok "step runs on every pull_request run that is not cancelled"
else
  fail "step lost its pull_request condition"
fi
if [[ "$step" == *$'\n        id: cost_hold\n'* ]]; then
  ok "step carries the id the hold-lift step reads its outputs by"
else
  fail "step lost its cost_hold id"
fi
# shellcheck disable=SC2016 # the ${{ }} text is workflow source, not shell
for env in 'BASE_SHA: ${{ github.event.pull_request.base.sha }}' 'HEAD_SHA: ${{ github.event.pull_request.head.sha }}'; do
  if [[ "$step" == *"$env"* ]]; then ok "step env carries $env"; else fail "step env lacks $env"; fi
done
order="$(grep -nE "^  ci-status:$|^      - name: ($NAME|Fail a pull request carrying the human-gated label|Fail a review-lane hold an untrusted account lifted)$" "$WORKFLOW" | cut -d: -f1 | paste -sd' ')"
read -r job_line cost_line gated_line lift_line <<<"$order"
if [[ -n "${lift_line:-}" && "$job_line" -lt "$cost_line" && "$cost_line" -lt "$gated_line" && "$gated_line" -lt "$lift_line" ]]; then
  ok "step sits in ci-status before the human-gated and hold-lift steps"
else
  fail "step is not inside ci-status before the human-gated step (lines: $order)"
fi
lift="$(awk '$0 == "      - name: Fail a review-lane hold an untrusted account lifted" { on = 1; next } on && /^        if: / { print; exit }' "$WORKFLOW")"
if [[ "$lift" == *"steps.cost_hold.outputs.cleared != 'true'"* ]]; then
  ok "the hold-lift step does not run once a recorded decision clears the hold"
else
  fail "the hold-lift step does not read cost_hold's cleared output: '$lift'"
fi

# The stub logs its arguments and answers from STUB_* variables; a read whose
# name is in STUB_FAIL fails.
mkdir -p "$TMP_ROOT/bin"
cat >"$TMP_ROOT/bin/gh" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$STUB_LOG"
failing() { [[ " ${STUB_FAIL:-} " == *" $1 "* ]] && exit 1; return 0; }
case "$*" in
*/contents/.work-item-tracker.json*)
  failing tracker
  [[ -n "${STUB_TRACKER+set}" ]] || { echo 'gh: Not Found (HTTP 404)' >&2; exit 1; }
  printf '%s\n' "$STUB_TRACKER"
  ;;
*/contents/.github/standards/trusted-actors/*) failing actors; printf '%s\n' "$STUB_ACTORS" ;;
*'-X DELETE'*/labels/*) failing delete ;;
*/issues/6419/labels*) failing labels; [[ -z "$STUB_LABELS" ]] || tr ',' '\n' <<<"$STUB_LABELS" ;;
*/issues/6419/events*) failing events; printf '%s\n' "$STUB_EVENTS" ;;
*'-X POST'*/issues/6419/comments*) failing post ;;
*/issues/6419/comments*) failing comments; printf '%s\n' "$STUB_COMMENTS" ;;
*/issues/comments/*)
  failing decision
  id="${*##*/issues/comments/}"
  jq -ce --arg id "${id##* }" '.[$id] // error' <<<"$STUB_DECISIONS" || { echo 'gh: Not Found (HTTP 404)' >&2; exit 1; }
  ;;
*/pulls/6419*) failing pull; printf '%s\n' "$STUB_PR" ;;
*graphql*closingIssuesReferences*) failing closing; printf '%s\n' "$STUB_CLOSING" ;;
*graphql*lastEditedAt*) failing edited; printf '%s\n' "$STUB_EDITED" ;;
*) exit 1 ;;
esac
EOF
printf '#!/usr/bin/env bash\n' >"$TMP_ROOT/bin/sleep"
chmod +x "$TMP_ROOT/bin/gh" "$TMP_ROOT/bin/sleep"

BASE=89abcdef0123456789abcdef0123456789abcdef
HEAD=0123456789abcdef0123456789abcdef01234567
OWNER_ID=153232337
LINK='https://github.com/o/r/issues/9306#issuecomment-111'
LANE='{"login":"github-actions[bot]","type":"Bot"}'
CLAUDE='{"login":"claude[bot]","type":"Bot"}'
APP='{"login":"melodic-automation-lanes[bot]","type":"Bot"}'
OWNER="{\"login\":\"owner\",\"id\":$OWNER_ID,\"type\":\"User\"}"
STRANGER='{"login":"someone","id":42,"type":"User"}'

comment() { jq -cn --argjson user "$1" --arg at "$2" --arg body "$3" '{user: $user, created_at: $at, body: $body}'; }
hold() {
  comment "$LANE" "$1" "<!-- claude-lane-hold lane=${3:-claude-review} sha=$HEAD criteria=$2 -->
**${3:-claude-review}** holds this pull request for a person ($2) at \`$HEAD\`.

A reason.

claude-lane: ${3:-claude-review}"
}
event() { jq -cn --arg e "$1" --argjson actor "$2" --arg at "$3" '{event: $e, actor: $actor, created_at: $at, label: {name: "needs-human"}}'; }
decision() {
  jq -cn --arg url "https://api.github.com/repos/o/r/issues/$1" --argjson user "$2" --arg at "$3" --arg body "$4" \
    '{issue_url: $url, user: $user, performed_via_github_app: null, created_at: $at, body: $body, node_id: "IC_1"}'
}

reset() {
  export STUB_FAIL='' STUB_LABELS='needs-human'
  export STUB_ACTORS="{\"actors\":[{\"kind\":\"human\",\"id\":$OWNER_ID},{\"kind\":\"bot\",\"id\":5}]}"
  export STUB_PR="{\"number\":6419,\"created_at\":\"2026-10-23T05:00:00Z\",\"body\":\"Closes #9306\\n\\n- Cost decision: [Q50]($LINK)\"}"
  export STUB_CLOSING='{"data":{"repository":{"pullRequest":{"closingIssuesReferences":{"totalCount":1,"nodes":[{"number":9306,"repository":{"nameWithOwner":"o/r"}}]}}}}}'
  STUB_DECISIONS="{\"111\":$(decision 9306 "$OWNER" 2026-10-23T13:14:57Z '**Decision recorded.** Cost: accepted.')}"
  export STUB_DECISIONS
  export STUB_EDITED='{"data":{"node":{"lastEditedAt":null}}}'
  STUB_EVENTS="[$(event labeled "$LANE" 2026-10-23T13:20:00Z)]"
  STUB_COMMENTS="[$(hold 2026-10-23T13:20:05Z cost)]"
  export STUB_EVENTS STUB_COMMENTS
  unset STUB_TRACKER
}

# expect <label> <want-cleared: yes|no> <want-delete: yes|no> <want-post: yes|no> [want-out]
expect() {
  local label="$1" out rc cleared deleted posted
  : >"$TMP_ROOT/log"
  : >"$TMP_ROOT/output"
  out="$(PATH="$TMP_ROOT/bin:$PATH" STUB_LOG="$TMP_ROOT/log" PR_NUMBER=6419 GITHUB_REPOSITORY=o/r \
    RUNNER_TEMP="$TMP_ROOT" GITHUB_OUTPUT="$TMP_ROOT/output" BASE_SHA="$BASE" HEAD_SHA="$HEAD" \
    bash -e "$TMP_ROOT/body.sh" 2>&1)" && rc=0 || rc=$?
  cleared=no deleted=no posted=no
  grep -qxF 'cleared=true' "$TMP_ROOT/output" && cleared=yes
  grep -q -- '-X DELETE repos/o/r/issues/6419/labels/needs-human' "$TMP_ROOT/log" && deleted=yes
  grep -q -- '-X POST repos/o/r/issues/6419/comments' "$TMP_ROOT/log" && posted=yes
  if [[ "$rc" -ne 0 ]]; then
    fail "$label: the step must never fail the job, got rc=$rc out='$out'"
  elif [[ "$cleared" != "$2" || "$deleted" != "$3" || "$posted" != "$4" ]]; then
    fail "$label: cleared=$cleared deleted=$deleted posted=$posted, wanted $2/$3/$4; out='$out'"
  elif [[ "$cleared" == yes ]] && ! grep -qxF "decision=${WANT_LINK:-$LINK}" "$TMP_ROOT/output"; then
    fail "$label: cleared without naming the decision: '$(cat "$TMP_ROOT/output")'"
  elif [[ -n "${5:-}" && "$out" != *"$5"* ]]; then
    fail "$label: output lacks '$5': '$out'"
  else
    ok "$label"
  fi
}

reset
expect "a cost-only hold with the owner's recorded decision is cleared" yes yes yes "$LINK"
post="$(sed -n '/-X POST/,/-X DELETE/p' "$TMP_ROOT/log" | grep -v -- '-X DELETE')"
if [[ "$post" == *"$LINK"* && "$post" != *"claude-lane-hold"* && "$post" != *"claude-lane:"* ]]; then
  ok "the removal comment cites the decision and is not itself a hold"
else
  fail "the removal comment: '$post'"
fi
if [[ "$(grep -n -- '-X POST' "$TMP_ROOT/log" | cut -d: -f1)" -lt "$(grep -n -- '-X DELETE' "$TMP_ROOT/log" | cut -d: -f1)" ]]; then
  ok "the comment is posted before the label comes off"
else
  fail "the label came off before the comment"
fi

reset
STUB_COMMENTS="[$(hold 2026-10-23T13:20:05Z cost),$(comment "$LANE" 2026-10-23T13:21:00Z "<!-- ci-status cost-hold-cleared decision=111 -->
ci-status took it off.")]"
expect "a decision already cited in a removal comment is not cited again" yes yes no
STUB_COMMENTS="[$(hold 2026-10-23T13:20:05Z cost),$(comment "$STRANGER" 2026-10-23T13:21:00Z "<!-- ci-status cost-hold-cleared decision=111 -->")]"
expect "a removal comment by a person does not count as posted" yes yes yes

reset
export STUB_LABELS=''
expect "with the label already off the hold reads cleared and nothing is written" yes no no

reset
STUB_PR='{"number":6419,"created_at":"2026-10-23T05:00:00Z","body":"Closes #9306"}'
expect "no decision cited in the body clears nothing" no no no
STUB_PR="{\"number\":6419,\"created_at\":\"2026-10-23T05:00:00Z\",\"body\":\"<!-- $LINK -->\"}"
expect "a decision cited only inside an HTML comment clears nothing" no no no
STUB_PR="{\"number\":6419,\"created_at\":\"2026-10-23T05:00:00Z\",\"body\":\"<!-- unclosed $LINK\"}"
expect "a decision cited inside an unclosed HTML comment clears nothing" no no no
STUB_PR='{"number":6419,"created_at":"2026-10-23T05:00:00Z","body":"https://github.com/x/r/issues/9306#issuecomment-111"}'
expect "a link to another repository clears nothing" no no no
STUB_PR='{"number":6419,"created_at":"2026-10-23T05:00:00Z","body":"https://github.com/o/r/issues/77#issuecomment-111"}'
expect "a link to an issue that does not close the pull request clears nothing" no no no

reset
STUB_DECISIONS="{\"111\":$(decision 9306 "$OWNER" 2026-10-23T04:00:00Z '**Decision recorded.** Cost: accepted.')}"
expect "an issue decision older than the pull request clears nothing" no no no
STUB_DECISIONS="{\"111\":$(decision 6419 "$OWNER" 2026-10-23T13:14:57Z '**Decision recorded.** Cost: accepted.')}"
STUB_PR="{\"number\":6419,\"created_at\":\"2026-10-23T05:00:00Z\",\"body\":\"https://github.com/o/r/pull/6419#issuecomment-111\"}"
WANT_LINK=https://github.com/o/r/pull/6419#issuecomment-111 expect "a decision on the pull request itself clears the hold" yes yes yes
reset
STUB_DECISIONS="{\"111\":$(decision 9306 "$STRANGER" 2026-10-23T13:14:57Z '**Decision recorded.** Cost: accepted.')}"
expect "a decision by someone off the trusted-actor list clears nothing" no no no
STUB_DECISIONS="{\"111\":$(decision 9306 "$OWNER" 2026-10-23T13:14:57Z '**Decision recorded.** Trust: accepted.')}"
expect "a decision recorded for something other than cost clears nothing" no no no
STUB_DECISIONS="{\"111\":$(jq -c '.performed_via_github_app = {"slug": "x"}' <<<"$(decision 9306 "$OWNER" 2026-10-23T13:14:57Z '**Decision recorded.** Cost: accepted.')")}"
expect "a decision posted through an App clears nothing" no no no
reset
export STUB_EDITED='{"data":{"node":{"lastEditedAt":"2026-10-23T13:30:00Z"}}}'
expect "an edited decision clears nothing" no no no
reset
export STUB_CLOSING='{"data":{"repository":{"pullRequest":{"closingIssuesReferences":{"totalCount":2,"nodes":[{"number":9306,"repository":{"nameWithOwner":"o/r"}},{"number":9307,"repository":{"nameWithOwner":"o/r"}}]}}}}}'
expect "a pull request closing two issues clears nothing from an issue decision" no no no

reset
STUB_COMMENTS="[$(hold 2026-10-23T13:20:05Z cost,trust-gate)]"
expect "a hold with cost and trust-gate clears nothing" no no no
STUB_COMMENTS="[$(hold 2026-10-23T13:20:05Z critical-security claude-security-review)]"
expect "a critical-security hold clears nothing" no no no
STUB_COMMENTS="[$(hold 2026-10-23T13:10:00Z trust-gate),$(hold 2026-10-23T13:20:05Z cost)]"
expect "an earlier trust-gate hold nobody trusted lifted keeps the label" no no no
STUB_EVENTS="[$(event labeled "$LANE" 2026-10-23T13:09:58Z),$(event unlabeled "$STRANGER" 2026-10-23T13:15:00Z),$(event labeled "$LANE" 2026-10-23T13:20:00Z)]"
expect "an untrusted removal of a trust-gate hold does not open the window" no no no
STUB_EVENTS="[$(event labeled "$LANE" 2026-10-23T13:09:58Z),$(event unlabeled "$OWNER" 2026-10-23T13:15:00Z),$(event labeled "$LANE" 2026-10-23T13:20:00Z)]"
expect "a trusted person's removal of the trust-gate hold opens a new window" yes yes yes
reset
STUB_COMMENTS="[$(comment "$CLAUDE" 2026-10-23T13:20:05Z "<!-- claude-lane-hold lane=claude-review sha=$HEAD criteria=cost -->
A claude[bot] hold.")]"
expect "a claude[bot] hold is not read as cost-only" no no no
STUB_COMMENTS="[$(comment "$LANE" 2026-10-23T13:20:05Z "<!-- claude-lane-hold lane=claude-review -->
No criteria.

claude-lane: claude-review")]"
expect "a hold with no criteria is not read as cost-only" no no no
STUB_COMMENTS="[$(comment "$LANE" 2026-10-23T13:20:05Z "Header first.
<!-- claude-lane-hold lane=claude-review sha=$HEAD criteria=cost -->

claude-lane: claude-review")]"
expect "a hold whose marker is not its first line is not read as cost-only" no no no
STUB_COMMENTS="[$(hold 2026-10-23T13:20:05Z cost),$(comment "$APP" 2026-10-23T13:22:00Z '<!-- work-items:escalation lane=pr-unblock kind=escalated -->
Escalated.')]"
expect "an escalation riding on the same label keeps it" no no no
STUB_COMMENTS='[]'
expect "a label with no hold comment clears nothing" no no no

reset
STUB_EVENTS="[$(event labeled "$OWNER" 2026-10-23T13:20:00Z)]"
expect "a label a person added clears nothing" no no no
STUB_EVENTS="[$(event labeled "$APP" 2026-10-23T13:20:00Z)]"
expect "a label the lanes App added clears nothing" no no no
STUB_EVENTS="[$(event labeled "$LANE" 2026-10-23T13:00:00Z)]"
expect "a lane label with no cost hold written right after it clears nothing" no no no
STUB_EVENTS='[]'
expect "a hold with no label event clears nothing" no no no

for read in tracker actors events comments pull closing decision edited; do
  reset
  export STUB_FAIL="$read"
  expect "an unreadable $read read clears nothing" no no no
done
reset
export STUB_FAIL=labels
expect "an unreadable label list reports the decision and writes nothing" yes no no "::warning::could not read the labels"
reset
export STUB_FAIL=delete
expect "a failed label removal still reports the decision for the steps after it" yes yes yes "::warning::"

test_harness::report
