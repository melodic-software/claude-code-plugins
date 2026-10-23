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
if [[ "$step" == *"if: \${{ !cancelled() && github.event_name == 'pull_request' && steps.human_gated.outputs.held == 'false' }}"* ]]; then
  ok "step runs only once the human-gated step read the label off"
else
  fail "step lost its condition on the human-gated step's held output"
fi
if [[ "$step" == *"continue-on-error"* ]]; then
  fail "step must not continue on error: its exit code is the hold"
else
  ok "step fails the job on its exit code"
fi
for env in 'BASE_SHA: ${{ github.event.pull_request.base.sha }}' 'HUMAN_GATED: ${{ steps.human_gated.outputs.label }}'; do
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
# page. A contents read of the trusted-actor list fails its first
# STUB_ACTORS_FAILS calls, then prints STUB_ACTORS. An events read fails when
# STUB_EVENTS_FAIL is set, else prints STUB_EVENTS (pages concatenated, as
# --paginate prints them).
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
*/contents/.github/standards/trusted-actors/trusted-actors.json*)
  [[ "$(grep -c '/contents/' "$STUB_LOG")" -gt "${STUB_ACTORS_FAILS:-0}" ]] || { echo 'gh: Server Error (HTTP 502)' >&2; exit 1; }
  printf '%s\n' "$STUB_ACTORS"
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
labeled() { jq -cn --arg l "$1" --arg at "$2" '{event: "labeled", created_at: $at, label: {name: $l}, actor: {id: 337595936, login: "x"}}'; }
OWNER_LIFT="$(unlabeled needs-human 2026-10-23T11:00:00Z 153232337 kyle-sexton)"
BOT_LIFT="$(unlabeled needs-human 2026-10-23T11:30:00Z 337595936 'melodic-automation-lanes[bot]')"
EARLY_LIFT="$(unlabeled needs-human 2026-10-23T09:00:00Z 153232337 kyle-sexton)"

# expect <label> <want-rc> [want-out] [refuse-out]; stubs come from the environment.
expect() {
  local label="$1" want_rc="$2" out rc
  : >"$TMP_ROOT/log"
  out="$(PATH="$TMP_ROOT/bin:$PATH" STUB_LOG="$TMP_ROOT/log" STUB_ACTORS="${STUB_ACTORS-$ACTORS}" PR_NUMBER=6419 \
    GITHUB_REPOSITORY=o/r HUMAN_GATED="${HUMAN_GATED-needs-human}" BASE_SHA="${BASE_SHA-$BASE}" \
    bash -e "$TMP_ROOT/body.sh" 2>&1)" && rc=0 || rc=$?
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

expect "a pull request no review lane held passes without reading events" 0 "No review lane has held #6419."
if grep -qE '/events|/contents/' "$TMP_ROOT/log"; then fail "events or actors read with no hold"; else ok "events and actors are read only after a hold"; fi
export STUB_COMMENTS="[$SPOOF,$NO_FOOTER]"
expect "a hold comment from a person or with no lane footer is not a hold" 0 "No review lane has held #6419."

export STUB_COMMENTS="[$OLD_HOLD,$HOLD]"
export STUB_EVENTS="[$(labeled needs-human 2026-10-23T09:59:00Z),$OWNER_LIFT]"
expect "a trusted person's removal after the hold passes" 0 "kyle-sexton, a person on the trusted-actor list, lifted"
if grep -qxF "api -H Accept: application/vnd.github.raw+json repos/o/r/contents/.github/standards/trusted-actors/trusted-actors.json?ref=$BASE" "$TMP_ROOT/log"; then
  ok "the trusted-actor list is read at the base commit"
else
  fail "the trusted-actor list was not read at the base commit: '$(sort -u "$TMP_ROOT/log")'"
fi
export STUB_EVENTS="[$OWNER_LIFT][$BOT_LIFT]"
expect "a later escalation's removal by a bot, across pages, does not undo the trusted lift" 0 "kyle-sexton, a person on the trusted-actor list, lifted"
export STUB_EVENTS="[$(unlabeled needs-human 2026-10-23T10:30:00Z 337595936 'melodic-automation-lanes[bot]'),$OWNER_LIFT]"
expect "a bot lifting the hold fails, whatever a trusted person did after" 1 \
  "::error::melodic-automation-lanes[bot] removed 'needs-human' from #6419 after a review lane held it, and is not a person on the trusted-actor list."
export STUB_EVENTS="[$BOT_LIFT,$(unlabeled needs-human 2026-10-23T10:30:00Z 4242 octocat)]"
expect "the first removal after the hold decides, not the list order" 1 "octocat removed 'needs-human'"
export STUB_EVENTS="[$EARLY_LIFT,$OWNER_LIFT]"
expect "a removal before the hold comment is not its lift" 0 "lifted the review-lane hold"
export STUB_EVENTS="[$EARLY_LIFT]"
expect "a removal before the newest hold comment does not lift it" 1 \
  "::error::a review lane held #6419 at 2026-10-23T10:00:00Z, and no removal of 'needs-human' since then is recorded."
export STUB_EVENTS="[]"
expect "a hold with no removal recorded fails closed" 1 "no removal of 'needs-human' since then is recorded"
export STUB_EVENTS="[$(unlabeled other-label 2026-10-23T11:00:00Z 153232337 kyle-sexton)]"
expect "removing another label does not lift the hold" 1 "no removal of 'needs-human'"
export HUMAN_GATED=owner-call STUB_EVENTS="[$(unlabeled owner-call 2026-10-23T11:00:00Z 153232337 kyle-sexton),$BOT_LIFT]"
expect "the label is the one the human-gated step resolved" 0 "kyle-sexton, a person on the trusted-actor list"
unset HUMAN_GATED

export STUB_EVENTS="[$OWNER_LIFT]"
export STUB_ACTORS='{"version":1,"actors":[{"id":153232337,"login":"kyle-sexton","kind":"bot"}]}'
expect "an id listed only as a bot is not a trusted person" 1 "the trusted-actor list at $BASE names no person"
export STUB_ACTORS='{"actors":[{"id":1,"login":"someone","kind":"human"}]}'
expect "a person missing from the base list is not trusted" 1 "kyle-sexton removed 'needs-human'"
export STUB_ACTORS='{not json'
expect "an unreadable trusted-actor list fails closed" 1 "names no person"
unset STUB_ACTORS
export STUB_ACTORS_FAILS=1
expect "a transient trusted-actor read failure is retried" 0 "lifted the review-lane hold"
export STUB_ACTORS_FAILS=3
expect "a trusted-actor list that never reads fails closed" 1 "::error::could not read the trusted-actor list at $BASE or the events of #6419"
unset STUB_ACTORS_FAILS
export STUB_EVENTS_FAIL=1
expect "an unreadable event list fails closed" 1 "could not read the trusted-actor list at $BASE or the events of #6419"
unset STUB_EVENTS_FAIL
export STUB_COMMENTS_FAIL=1
expect "an unreadable comment list fails closed" 1 "::error::could not read the comments of #6419"
unset STUB_COMMENTS_FAIL
export BASE_SHA=main
expect "a base that is not a commit SHA fails closed" 1 "::error::the base commit 'main' is not a commit SHA"
unset BASE_SHA

test_harness::report
