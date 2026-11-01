#!/usr/bin/env bash
# Runs the `Fail a review-lane hold an untrusted account lifted` step body of
# .github/workflows/pr-require-checks.yml's ci-status under the shell Actions
# gives a step with no `shell:` (bash -e), against stub `gh` and `sleep`.
#
# Once a review lane has held a pull request, ci-status passes with the
# human-gated label off only when the first removal of that label after the
# newest hold comment was made by a `human` of the base commit's trusted-actor
# list. It fails closed when it cannot tell.
# test-scope: .github/workflows/pr-require-checks.yml
# test-scope: .work-item-tracker.json
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
ci_gh_read::install "$WORKFLOW" "$TMP_ROOT" budget || fail "the ci-status gh_read helper step is missing or fails"

NAME='Fail a review-lane hold an untrusted account lifted'
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
if [[ "$step" == *"if: \${{ !cancelled() && github.event_name == 'pull_request' && steps.human_gated.outputs.held == 'false' && steps.cost_hold.outputs.cleared != 'true' }}"* ]]; then
  ok "step runs only once the human-gated step read the label off and no recorded cost decision cleared the hold"
else
  fail "step lost its condition on the human-gated step's held output"
fi
# On a draft the human-gated step skips, so its held output is empty, not
# 'false', and this step skips with it: it makes no read on a draft.
gated="$(awk '$0 == "      - name: Fail a pull request carrying the human-gated label" { on = 1; next } on && /^        if: / { print; exit }' "$WORKFLOW")"
if [[ "$gated" == *"github.event.pull_request.draft != true"* ]]; then
  ok "the human-gated step skips on a draft, so this step does too"
else
  fail "the human-gated step lost its draft skip: '$gated'"
fi
if [[ "$step" == *"continue-on-error"* ]]; then
  fail "step must not continue on error: its exit code is the hold"
else
  ok "step fails the job on its exit code"
fi
# shellcheck disable=SC2016 # the ${{ }} text is workflow source, not shell
for env in 'BASE_SHA: ${{ github.event.pull_request.base.sha }}' 'HEAD_SHA: ${{ github.event.pull_request.head.sha }}' 'HUMAN_GATED: ${{ steps.human_gated.outputs.label }}' \
  "BASE_CONFIG: \${{ steps.base_config.outcome == 'success' && format('{0}/base-config', github.workspace) || '' }}"; do
  if [[ "$step" == *"$env"* ]]; then ok "step env carries $env"; else fail "step env lacks $env"; fi
done
order="$(grep -nE "^  ci-status:$|^      - name: (Fail a pull request carrying the human-gated label|$NAME|Aggregate lane results)$" "$WORKFLOW" | cut -d: -f1 | paste -sd' ')"
read -r job_line gated_line lift_line agg_line <<<"$order"
if [[ -n "${agg_line:-}" && "$job_line" -lt "$gated_line" && "$gated_line" -lt "$lift_line" && "$lift_line" -lt "$agg_line" ]]; then
  ok "step sits in ci-status after the human-gated step, before the aggregate"
else
  fail "step is not inside ci-status between the human-gated step and the aggregate (lines: $order)"
fi

# The stub logs its arguments. A comments read fails when STUB_COMMENTS_FAIL is
# set, else answers the STUB_COMMENTS array. An events read fails when STUB_EVENTS_FAIL is set, else prints
# STUB_EVENTS (pages concatenated, as --paginate prints them). The base
# commit's config is a fixture directory holding STUB_ACTORS as the
# trusted-actor list; STUB_CHECKOUT_FAILED leaves BASE_CONFIG empty, as a
# failed checkout does.
mkdir -p "$TMP_ROOT/bin"
cat >"$TMP_ROOT/bin/gh" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$STUB_LOG"
case "$*" in
*/comments*)
  [[ -z "${STUB_COMMENTS_FAIL:-}" ]] || exit 1
  printf '%s\n' "${STUB_COMMENTS:-[]}"
  ;;
*/events*)
  [[ -z "${STUB_EVENTS_FAIL:-}" ]] || exit 1
  printf '%s\n' "${STUB_EVENTS:-[]}"
  ;;
*) exit 1 ;;
esac
EOF
printf '#!/usr/bin/env bash\n' >"$TMP_ROOT/bin/sleep"
chmod +x "$TMP_ROOT/bin/gh" "$TMP_ROOT/bin/sleep"

BASE=89abcdef0123456789abcdef0123456789abcdef
ACTORS='{"version":1,"actors":[{"id":153232337,"login":"kyle-sexton","kind":"human"},{"id":337595936,"login":"melodic-automation-lanes[bot]","kind":"bot"}]}'
LANE='{"login":"github-actions[bot]","type":"Bot"}'
comment() { jq -cn --arg body "$2" --arg at "$3" --argjson user "$1" '{user: $user, body: $body, created_at: $at}'; }
HOLD="$(comment "$LANE" $'<!-- claude-lane-hold lane=claude-review sha=bbbb criteria=trust-gate -->\nHeld.\n\nclaude-lane: claude-review' 2026-10-23T10:00:00Z)"
OLD_HOLD="$(comment "$LANE" $'<!-- claude-lane-hold lane=claude-security-review sha=aaaa criteria=cost -->\nHeld.\nclaude-lane: claude-security-review' 2026-10-22T10:00:00Z)"
SPOOF="$(comment '{"login":"someone","type":"User"}' $'<!-- claude-lane-hold lane=x -->\nclaude-lane: claude-review' 2026-10-23T12:00:00Z)"
NO_FOOTER="$(comment "$LANE" $'<!-- claude-lane-hold lane=claude-review -->\nNo footer.' 2026-10-23T12:00:00Z)"
# unlabeled <label> <at> <actor-id> <login>
unlabeled() { jq -cn --arg l "$1" --arg at "$2" --argjson id "$3" --arg login "$4" '{event: "unlabeled", created_at: $at, label: {name: $l}, actor: {id: $id, login: $login}}'; }
labeled() { jq -cn --arg l "$1" --arg at "$2" --arg login "${3:-melodic-automation-lanes[bot]}" '{event: "labeled", created_at: $at, label: {name: $l}, actor: {id: 1, login: $login}}'; }
OWNER_LIFT="$(unlabeled needs-human 2026-10-23T11:00:00Z 153232337 kyle-sexton)"
BOT_LIFT="$(unlabeled needs-human 2026-10-23T11:30:00Z 337595936 'melodic-automation-lanes[bot]')"
EARLY_LIFT="$(unlabeled needs-human 2026-10-23T09:00:00Z 153232337 kyle-sexton)"

# expect <label> <want-rc> [want-out] [refuse-out]; stubs come from the environment.
expect() {
  local label="$1" want_rc="$2" out rc config="$TMP_ROOT/base-config"
  : >"$TMP_ROOT/log"
  rm -rf "$config" "$TMP_ROOT/pr-reads"
  mkdir -p "$config/.github/standards/trusted-actors"
  printf '%s\n' "${STUB_ACTORS-$ACTORS}" >"$config/.github/standards/trusted-actors/trusted-actors.json"
  # The base commit's clear-escalations.mjs, stubbed: its recheckStaleHold
  # records what it was given and answers STUB_PREDICATE (pass, else the hold
  # stands); a run of the module as a script is recorded too. Absent when
  # STUB_NO_PREDICATE is set. clear-escalations-recheck.test.mjs tests the
  # real one.
  if [[ -z "${STUB_NO_PREDICATE:-}" ]]; then
    mkdir -p "$config/.github/scripts/pr-merge"
    cat >"$config/.github/scripts/pr-merge/clear-escalations.mjs" <<'JS'
import { appendFileSync } from "node:fs";
import { pathToFileURL } from "node:url";
const { PR_NUMBER, HEAD_SHA, CLEARED_SHA, HUMAN_GATED, TRUSTED_ACTORS_PATH, STUB_LOG, STUB_PREDICATE } = process.env;
if (import.meta.url === pathToFileURL(process.argv[1] ?? "").href) {
  appendFileSync(STUB_LOG, "clear-escalations main ran\n");
}
export async function recheckStaleHold() {
  appendFileSync(STUB_LOG, `predicate pr=${PR_NUMBER} head=${HEAD_SHA} cleared=${CLEARED_SHA} label=${HUMAN_GATED} trusted=${TRUSTED_ACTORS_PATH}\n`);
  console.log(`stale-review-hold: stub ${STUB_PREDICATE ?? "unset"}`);
  return STUB_PREDICATE === "pass" ? 0 : 1;
}
JS
  fi
  [[ -z "${STUB_CHECKOUT_FAILED:-}" ]] || config=
  out="$(PATH="$TMP_ROOT/bin:$PATH" STUB_LOG="$TMP_ROOT/log" PR_NUMBER=6419 \
    GITHUB_REPOSITORY=o/r HUMAN_GATED="${HUMAN_GATED-needs-human}" BASE_SHA="${BASE_SHA-$BASE}" \
    BASE_CONFIG="$config" bash -e "$TMP_ROOT/body.sh" 2>&1)" && rc=0 || rc=$?
  if grep -q '/contents/' "$TMP_ROOT/log"; then
    fail "$label: the trusted-actor list was read through the API"
    return
  fi
  if [[ "$rc" -ne "$want_rc" ]]; then
    fail "$label: expected rc=$want_rc got rc=$rc out='$out'"
  elif [[ -n "${3:-}" && "$out" != *"$3"* ]]; then
    fail "$label: output lacks '$3': '$out'"
  elif [[ -n "${4:-}" && "$out" == *"$4"* ]]; then
    fail "$label: output has '$4': '$out'"
  else
    ok "$label"
  fi
}

expect "a pull request no review lane held passes" 0 "No review lane has held #6419."
if [[ "$(grep -c '^api ' "$TMP_ROOT/log")" -eq 2 ]] && grep -q '^api repos/o/r/issues/6419/comments' "$TMP_ROOT/log" &&
  grep -q '^api repos/o/r/issues/6419/events' "$TMP_ROOT/log"; then
  ok "with no hold the step makes two reads, the comments and the events, both needed for that verdict"
else
  fail "with no hold the step's reads are not exactly comments and events: '$(cat "$TMP_ROOT/log")'"
fi
STUB_CHECKOUT_FAILED=1 expect "with no hold the actor list is not needed, so a failed base checkout passes" 0 "No review lane has held #6419."
export STUB_EVENTS
STUB_EVENTS="[$(labeled needs-human 2026-10-23T09:00:00Z),$BOT_LIFT]"
expect "a label the lanes App added (an escalation) is not a review-lane hold" 0 "No review lane has held #6419."
export STUB_COMMENTS="[$SPOOF,$NO_FOOTER]"
expect "a hold comment from a person or with no lane footer is not a hold" 0 "No review lane has held #6419."

export STUB_COMMENTS="[$OLD_HOLD,$HOLD]"
STUB_EVENTS="[$(labeled needs-human 2026-10-23T09:59:00Z),$OWNER_LIFT]"
expect "a trusted person's removal after the hold passes" 0 "kyle-sexton, a person on the trusted-actor list, lifted"
STUB_EVENTS="[$(labeled needs-human 2026-10-23T09:59:00Z),$(jq -c '.performed_via_github_app = null' <<<"$OWNER_LIFT")]"
expect "a trusted person's direct removal (performed_via_github_app null) passes" 0 "kyle-sexton, a person on the trusted-actor list, lifted"
STUB_EVENTS="[$(labeled needs-human 2026-10-23T09:59:00Z),$(jq -c '.performed_via_github_app = {slug: "some-app"}' <<<"$OWNER_LIFT")]"
expect "a removal an App made for a trusted person fails, naming the App" 1 \
  "::error::kyle-sexton removed 'needs-human' from #6419 through the App some-app after a review lane held it"
export STUB_EVENTS="[$OWNER_LIFT][$BOT_LIFT]"
expect "a later escalation's removal by a bot, across pages, does not undo the trusted lift" 0 "kyle-sexton, a person on the trusted-actor list, lifted"
STUB_EVENTS="[$(unlabeled needs-human 2026-10-23T10:30:00Z 337595936 'melodic-automation-lanes[bot]'),$OWNER_LIFT]"
expect "a bot lifting the hold fails, whatever a trusted person did after" 1 \
  "::error::melodic-automation-lanes[bot] removed 'needs-human' from #6419 after a review lane held it, and is not a person on the trusted-actor list."
STUB_EVENTS="[$BOT_LIFT,$(unlabeled needs-human 2026-10-23T10:30:00Z 4242 octocat)]"
expect "the first removal after the hold decides, not the list order" 1 "octocat removed 'needs-human'"
export STUB_EVENTS="[$EARLY_LIFT,$OWNER_LIFT]"
expect "a removal before the hold comment is not its lift" 0 "lifted the review-lane hold"
export STUB_EVENTS="[$EARLY_LIFT]"
expect "a removal before the newest hold comment does not lift it" 1 \
  "::error::a review lane held #6419 at 2026-10-23T10:00:00Z, and no removal of 'needs-human' since then is recorded."
export STUB_EVENTS="[]"
expect "a hold with no removal recorded fails closed" 1 "no removal of 'needs-human' since then is recorded"
STUB_EVENTS="[$(unlabeled other-label 2026-10-23T11:00:00Z 153232337 kyle-sexton)]"
expect "removing another label does not lift the hold" 1 "no removal of 'needs-human'"
export HUMAN_GATED=owner-call
STUB_EVENTS="[$(unlabeled owner-call 2026-10-23T11:00:00Z 153232337 kyle-sexton),$BOT_LIFT]"
expect "the label is the one the human-gated step resolved" 0 "kyle-sexton, a person on the trusted-actor list"
unset HUMAN_GATED

# The label events anchor the hold too: they cannot be deleted or edited.
STUB_COMMENTS="[]"
STUB_EVENTS="[$(labeled needs-human 2026-10-23T10:00:00Z 'github-actions[bot]'),$BOT_LIFT]"
expect "a deleted hold comment leaves the lane's label event as the hold" 1 "melodic-automation-lanes[bot] removed 'needs-human'"
STUB_EVENTS="[$(labeled needs-human 2026-10-23T10:00:00Z 'claude[bot]'),$OWNER_LIFT]"
expect "a trusted lift of a claude[bot] label passes with no comment" 0 "lifted the review-lane hold"
STUB_COMMENTS="[$HOLD]"
STUB_EVENTS="[$OWNER_LIFT,$(labeled needs-human 2026-10-23T11:10:00Z 'github-actions[bot]'),$BOT_LIFT]"
expect "a review re-run that labels the same head again needs its own trusted lift" 1 "melodic-automation-lanes[bot] removed 'needs-human'"
# Recovery: a trusted person adds the label back and removes it.
TRUSTED_RELABEL="$(jq -cn '{event: "labeled", created_at: "2026-10-23T12:00:00Z", label: {name: "needs-human"}, actor: {id: 153232337, login: "kyle-sexton"}}')"
STUB_EVENTS="[$BOT_LIFT,$TRUSTED_RELABEL,$(unlabeled needs-human 2026-10-23T12:05:00Z 153232337 kyle-sexton)]"
expect "a trusted person re-adding and removing the label recovers a hold a bot lifted" 0 "lifted the review-lane hold"
STUB_EVENTS="[$BOT_LIFT,$(labeled needs-human 2026-10-23T12:00:00Z),$(unlabeled needs-human 2026-10-23T12:05:00Z 153232337 kyle-sexton)]"
expect "a bot re-adding the label does not move the hold" 1 "melodic-automation-lanes[bot] removed"
STUB_EVENTS="[$BOT_LIFT,$TRUSTED_RELABEL,$(unlabeled needs-human 2026-10-23T12:05:00Z 4242 octocat)]"
expect "an untrusted removal after a trusted re-add fails" 1 "octocat removed 'needs-human'"

# A stale hold the lanes App cleared (clear-escalations.mjs stale-review-hold,
# owner brief Part A2): the App's own removal lifts it only after its own
# marked comment names a head no hold comment names.
OLD_SHA=$(printf 'c%.0s' {1..40})
NEW_SHA=$(printf 'd%.0s' {1..40})
APP_USER='{"login":"melodic-automation-lanes[bot]","type":"Bot","id":337595936}'
held_at() { comment "$LANE" "<!-- claude-lane-hold lane=claude-security-review sha=$1 criteria=critical-security -->"$'\nHeld.\n\nclaude-lane: claude-security-review' "$2"; }
cleared_for() { comment "${2:-$APP_USER}" "<!-- pr-pipeline needs-human-cleared reason=stale-review-hold head=$1 -->"$'\nA review lane held this pull request at an earlier head.' "${3:-2026-10-23T11:29:00Z}"; }
STALE_HOLD="$(held_at "$OLD_SHA" 2026-10-23T10:00:00Z)"
export LANES_APP_ID=337595936
export HEAD_SHA="$NEW_SHA"
export STUB_PREDICATE=pass
STUB_EVENTS="[$BOT_LIFT]"
STUB_COMMENTS="[$STALE_HOLD,$(cleared_for "$NEW_SHA")]"
expect "the lanes App's removal after its stale-review-hold comment for an unheld head passes" 0 \
  "melodic-automation-lanes[bot] cleared the review-lane hold on #6419 as stale: its marker names $NEW_SHA"
STUB_COMMENTS="[$STALE_HOLD,$(cleared_for "$OLD_SHA")]"
expect "a stale-review-hold comment naming the held head does not lift it" 1 "melodic-automation-lanes[bot] removed 'needs-human'"
STUB_COMMENTS="[$(held_at "$NEW_SHA" 2026-10-23T09:30:00Z),$STALE_HOLD,$(cleared_for "$NEW_SHA")]"
expect "a stale-review-hold comment naming a head an earlier hold names does not lift it" 1 "melodic-automation-lanes[bot] removed 'needs-human'"
STUB_COMMENTS="[$STALE_HOLD]"
expect "the lanes App's removal with no stale-review-hold comment still fails" 1 "melodic-automation-lanes[bot] removed 'needs-human'"
STUB_COMMENTS="[$STALE_HOLD,$(cleared_for "$NEW_SHA" "" 2026-10-23T09:00:00Z)]"
expect "a stale-review-hold comment from before the hold does not lift it" 1 "melodic-automation-lanes[bot] removed 'needs-human'"
STUB_COMMENTS="[$STALE_HOLD,$(cleared_for "$NEW_SHA" '{"login":"someone","type":"User","id":4242}')]"
expect "the marker in another account's comment does not lift it" 1 "melodic-automation-lanes[bot] removed 'needs-human'"
STUB_COMMENTS="[$HOLD,$(cleared_for "$NEW_SHA")]"
expect "a hold comment whose head does not parse keeps it" 1 "melodic-automation-lanes[bot] removed 'needs-human'"
STUB_COMMENTS="[$STALE_HOLD,$(cleared_for "$NEW_SHA")]"
STUB_EVENTS="[$(jq -c '.performed_via_github_app = {slug: "some-app"}' <<<"$BOT_LIFT")]"
expect "the lanes App's removal through another App does not lift it" 1 "melodic-automation-lanes[bot] removed 'needs-human'"
STUB_EVENTS="[$(unlabeled needs-human 2026-10-23T11:30:00Z 4242 octocat)]"
expect "another account's removal after the App's comment does not lift it" 1 "octocat removed 'needs-human'"
STUB_EVENTS="[$BOT_LIFT]"
LANES_APP_ID='' expect "with no lanes App id the App's removal fails closed" 1 "melodic-automation-lanes[bot] removed 'needs-human'"
STUB_ACTORS='{"version":1,"actors":[{"id":153232337,"login":"kyle-sexton","kind":"human"}]}' \
  expect "a lanes App id the base list does not name fails closed" 1 "melodic-automation-lanes[bot] removed 'needs-human'"
# The race the security review of 990c1941 found: a lane held the current
# head after the App judged it, under the label already on, before its delete.
STUB_COMMENTS="[$STALE_HOLD,$(held_at "$NEW_SHA" 2026-10-23T11:20:00Z),$(cleared_for "$OLD_SHA")]"
expect "a hold naming this head, written before the App's marker, keeps it whatever head the marker names" 1 "melodic-automation-lanes[bot] removed 'needs-human'"
OTHER_SHA=$(printf 'e%.0s' {1..40})
STUB_COMMENTS="[$STALE_HOLD,$(held_at "$NEW_SHA" 2026-10-23T11:20:00Z),$(cleared_for "$OTHER_SHA")]"
expect "a hold naming this head keeps it beside a marker for an unheld head" 1 "melodic-automation-lanes[bot] removed 'needs-human'"
# A later clean push: the marker names the head the App judged, this head is
# a newer one no hold names, so its own reviews decide (not strict equality).
STUB_COMMENTS="[$STALE_HOLD,$(cleared_for "$NEW_SHA")]"
HEAD_SHA="$OTHER_SHA" expect "a later head no hold names passes after the App's clear of an earlier one" 0 \
  "melodic-automation-lanes[bot] cleared the review-lane hold on #6419 as stale"
if grep -qxF "predicate pr=6419 head=$OTHER_SHA cleared=$NEW_SHA label=needs-human trusted=$TMP_ROOT/base-config/.github/standards/trusted-actors/trusted-actors.json" "$TMP_ROOT/log"; then
  ok "at a later head the predicate judges the head the App's marker names"
else
  fail "at a later head the predicate was not given the marker's head: '$(cat "$TMP_ROOT/log")'"
fi
# Only the newest marker before the removal names the cleared head.
STUB_COMMENTS="[$STALE_HOLD,$(cleared_for "$OTHER_SHA" "" 2026-10-23T11:10:00Z),$(cleared_for "$NEW_SHA")]"
expect "the newest marker before the removal is the one judged" 0 "its marker names $NEW_SHA,"
# A hold a person already lifted counts for nothing (thread PRRT_kwDOTCGFQM6xmJXy):
# an old unparsable hold, its trusted lift, then the lane's new label and hold.
STUB_COMMENTS="[$(comment "$LANE" $'<!-- claude-lane-hold lane=claude-review sha=bbbb criteria=trust-gate -->\nHeld.\n\nclaude-lane: claude-review' 2026-10-22T10:00:00Z),$STALE_HOLD,$(cleared_for "$NEW_SHA")]"
STUB_EVENTS="[$(unlabeled needs-human 2026-10-22T12:00:00Z 153232337 kyle-sexton),$(labeled needs-human 2026-10-23T09:59:00Z 'github-actions[bot]'),$BOT_LIFT]"
expect "an unparsable hold a person lifted before the label went on again does not block the App's clear" 0 \
  "melodic-automation-lanes[bot] cleared the review-lane hold on #6419 as stale"
STUB_COMMENTS="[$(held_at "$NEW_SHA" 2026-10-22T10:00:00Z),$STALE_HOLD,$(cleared_for "$NEW_SHA")]"
expect "a lifted hold naming the head the App cleared does not block it" 0 \
  "melodic-automation-lanes[bot] cleared the review-lane hold on #6419 as stale"
STUB_EVENTS="[$(labeled needs-human 2026-10-23T09:59:00Z 'github-actions[bot]'),$BOT_LIFT]"
expect "with no removal before the label, every hold comment counts" 1 "melodic-automation-lanes[bot] removed 'needs-human'"
STUB_EVENTS="[$BOT_LIFT]"
HEAD_SHA='' expect "an empty head fails the App's removal closed" 1 "melodic-automation-lanes[bot] removed 'needs-human'"
HEAD_SHA=main expect "a head that is not a commit SHA fails the App's removal closed" 1 "melodic-automation-lanes[bot] removed 'needs-human'"
# The marker only points ci-status at the hold: the base commit's
# clear-escalations.mjs recheckStaleHold judges it again at this head (coordinator direction:
# never take the App's judgment on trust).
STUB_COMMENTS="[$STALE_HOLD,$(cleared_for "$NEW_SHA")]"
STUB_PREDICATE=stands expect "a valid marker whose predicate now finds the hold standing fails" 1 \
  "melodic-automation-lanes[bot] removed 'needs-human'"
if grep -qxF "predicate pr=6419 head=$NEW_SHA cleared=$NEW_SHA label=needs-human trusted=$TMP_ROOT/base-config/.github/standards/trusted-actors/trusted-actors.json" "$TMP_ROOT/log"; then
  ok "the predicate runs at this head with the base commit's trusted-actor list and the resolved label"
  if grep -q 'clear-escalations main ran' "$TMP_ROOT/log"; then fail "importing the base module ran its sweep"; else ok "importing the base module runs no sweep"; fi
else
  fail "the predicate's inputs are not this head, label and base list: '$(cat "$TMP_ROOT/log")'"
fi
STUB_NO_PREDICATE=1 expect "a base commit with no clear-escalations.mjs fails the App's removal closed" 1 \
  "melodic-automation-lanes[bot] removed 'needs-human'"
STUB_COMMENTS="[$STALE_HOLD]"
expect "with no marker the predicate is not run" 1 "melodic-automation-lanes[bot] removed 'needs-human'"
if grep -q '^predicate ' "$TMP_ROOT/log"; then fail "the predicate ran with no marker"; else ok "the predicate runs only behind a marker"; fi
unset LANES_APP_ID HEAD_SHA STUB_PREDICATE

export STUB_EVENTS="[$OWNER_LIFT]"
export STUB_ACTORS='{"version":1,"actors":[{"id":153232337,"login":"kyle-sexton","kind":"bot"}]}'
expect "an id listed only as a bot is not a trusted person" 1 "the trusted-actor list at $BASE names no person"
export STUB_ACTORS='{"actors":[{"id":1,"login":"someone","kind":"human"}]}'
expect "a person missing from the base list is not trusted" 1 "kyle-sexton removed 'needs-human'"
export STUB_ACTORS='{not json'
expect "an unreadable trusted-actor list fails closed" 1 "names no person"
unset STUB_ACTORS
STUB_CHECKOUT_FAILED=1 expect "a hold with a failed base checkout fails closed" 1 "::error::could not read the trusted-actor list at $BASE; re-run this run."
export STUB_EVENTS_FAIL=1
expect "an unreadable event list fails closed" 1 "::error::could not read the events of #6419; re-run this run."
unset STUB_EVENTS_FAIL
export STUB_COMMENTS_FAIL=1
expect "an unreadable comment list fails closed" 1 "::error::could not read the comments of #6419"
unset STUB_COMMENTS_FAIL
export BASE_SHA=main
expect "a base that is not a commit SHA fails closed" 1 "::error::the base commit 'main' is not a commit SHA"
unset BASE_SHA

# The stub above stands in for the base commit's clear-escalations.mjs, so a
# real import the sparse base_config checkout leaves out would only fail on a
# runner. Copy the sparse list's files alone and import the real module.
SPARSE="$TMP_ROOT/sparse"
mapfile -t sparse_paths < <(awk '/^        id: base_config$/ { on = 1 } on && /sparse-checkout: \|$/ { list = 1; next }
  list && /^            \// { print substr($0, 14); next } list { exit }' "$WORKFLOW")
if [[ "${#sparse_paths[@]}" -eq 0 ]]; then
  fail "no base_config sparse-checkout list in $WORKFLOW"
else
  for rel in "${sparse_paths[@]}"; do
    if [[ -f "$ROOT/$rel" ]]; then
      mkdir -p "$SPARSE/$(dirname "$rel")"
      cp "$ROOT/$rel" "$SPARSE/$rel"
    fi
  done
  # The path goes in the environment: as argv[1] the module would run as the script.
  if out="$(SPARSE_MODULE="$SPARSE/.github/scripts/pr-merge/clear-escalations.mjs" node --input-type=module -e 'await import(process.env.SPARSE_MODULE);' 2>&1)"; then
    ok "the base_config sparse checkout holds every file clear-escalations.mjs imports"
  else
    fail "clear-escalations.mjs does not load from the base_config sparse checkout: $out"
  fi
fi

test_harness::report
