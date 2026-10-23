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
if [[ "$step" == *"continue-on-error"* ]]; then
  fail "step must not continue on error: its exit code is the hold"
else
  ok "step fails the job on its exit code"
fi
# shellcheck disable=SC2016 # the ${{ }} text is workflow source, not shell
for env in 'BASE_SHA: ${{ github.event.pull_request.base.sha }}' 'HUMAN_GATED: ${{ steps.human_gated.outputs.label }}' \
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
# set, else applies the --jq filter to the STUB_COMMENTS array, as gh does per
# page. An events read fails when STUB_EVENTS_FAIL is set, else prints
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
  while [[ $# -gt 0 && "$1" != --jq ]]; do shift; done
  jq -r "$2" <<<"${STUB_COMMENTS:-[]}"
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
  rm -rf "$config"
  mkdir -p "$config/.github/standards/trusted-actors"
  printf '%s\n' "${STUB_ACTORS-$ACTORS}" >"$config/.github/standards/trusted-actors/trusted-actors.json"
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

test_harness::report
