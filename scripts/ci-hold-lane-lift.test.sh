#!/usr/bin/env bash
# Runs the `Clear a review-lane security hold its lane re-reviewed clean` step
# body of .github/workflows/pr-require-checks.yml's ci-status under the shell
# Actions gives a step with no `shell:` (bash -e), against stub `gh` and
# `sleep`.
#
# Owner decision Q15 (a), 2026-10-26: a review lane's critical-security hold
# at an older head comes off once that lane's complete review of the current
# head finds no CRITICAL finding and no open IMPORTANT security finding. Only
# a label github-actions[bot] added, right before a held review, comes off;
# a person's, another lane's, and anything unread keep it. The verdict is the
# base's merge-holds.mjs laneLift (merge-holds.test.mjs pins it case by case);
# this test pins the reads that feed it and the write that follows.
# test-scope: .github/workflows/pr-require-checks.yml
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORKFLOW="$ROOT/.github/workflows/pr-require-checks.yml"

# shellcheck source=lib/test-harness.sh
. "$ROOT/scripts/lib/test-harness.sh"

TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT

NAME='Clear a review-lane security hold its lane re-reviewed clean'
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
if [[ "$step" == *"if: \${{ !cancelled() && github.event_name == 'pull_request' }}"* && "$step" == *$'\n        id: lane_lift\n'* ]]; then
  ok "step runs on every pull_request run and carries the id the hold-lift step reads"
else
  fail "step lost its pull_request condition or its lane_lift id"
fi
order="$(grep -nE "^  ci-status:$|^      - name: (Clear a cost-only review hold the owner decided|$NAME|Fail a pull request carrying the human-gated label|Fail a review-lane hold an untrusted account lifted)$" "$WORKFLOW" | cut -d: -f1 | paste -sd' ')"
read -r job_line cost_line lift_line gated_line untrusted_line <<<"$order"
if [[ -n "${untrusted_line:-}" && "$job_line" -lt "$cost_line" && "$cost_line" -lt "$lift_line" && "$lift_line" -lt "$gated_line" && "$gated_line" -lt "$untrusted_line" ]]; then
  ok "step sits in ci-status after the cost step and before the human-gated and hold-lift steps"
else
  fail "step is out of place in ci-status (lines: $order)"
fi
untrusted="$(awk '$0 == "      - name: Fail a review-lane hold an untrusted account lifted" { on = 1; next } on && /^        if: / { print; exit }' "$WORKFLOW")"
if [[ "$untrusted" == *"steps.lane_lift.outputs.cleared != 'true'"* ]]; then
  ok "the hold-lift step does not run once the lane's clean re-review cleared the hold"
else
  fail "the hold-lift step does not read lane_lift's cleared output: '$untrusted'"
fi

mkdir -p "$TMP_ROOT/bin"
cat >"$TMP_ROOT/bin/gh" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$STUB_LOG"
failing() { [[ " ${STUB_FAIL:-} " == *" $1 "* ]] && exit 1; return 0; }
from() { jq -ce --arg k "$2" '.[$k] // error' <<<"$1" || { echo 'gh: Not Found (HTTP 404)' >&2; exit 1; }; }
key() { local a; for a in "${@:2}"; do [[ "$a" == */"$1"/* ]] && { a="${a##*/"$1"/}"; printf '%s' "${a%%[/?]*}"; return; }; done; }
case "$*" in
*'-X DELETE'*/labels/*) failing delete ;;
*/issues/6419/labels*) failing labels; [[ -z "$STUB_LABELS" ]] || tr ',' '\n' <<<"$STUB_LABELS" ;;
*/issues/6419/events*) failing events; printf '%s\n' "$STUB_EVENTS" ;;
*'-X POST'*/issues/6419/comments*) failing post ;;
*/issues/6419/comments*) failing comments; printf '%s\n' "$STUB_COMMENTS" ;;
*/actions/workflows/*/runs*)
  failing runs
  [[ "$*" == *'branch=fix%2Fsec&'* ]] || exit 1
  from "$STUB_RUNS" "$(key workflows "$@")"
  ;;
*/compare/"$BASE_SHA..."*) failing compare; args="$*"; from "$STUB_COMPARE" "${args##*...}" ;;
*/actions/runs/*/jobs*) failing jobs; from "$STUB_JOBS" "$(key runs "$@")" ;;
*/check-runs/*/annotations*) failing notes; from "$STUB_NOTES" "$(key check-runs "$@")" ;;
*/pulls/6419*) failing pull; printf '%s\n' "$STUB_PR" ;;
*graphql*COMMENT_DELETED_EVENT*) failing deleted; printf '%s\n' "$STUB_DELETED" ;;
*graphql*reviewThreads*) failing threads; printf '%s\n' "$STUB_THREADS" ;;
*) exit 1 ;;
esac
EOF
printf '#!/usr/bin/env bash\n' >"$TMP_ROOT/bin/sleep"
chmod +x "$TMP_ROOT/bin/gh" "$TMP_ROOT/bin/sleep"

BASE=89abcdef0123456789abcdef0123456789abcdef
HEAD=0123456789abcdef0123456789abcdef01234567
OLD=fedcba9876543210fedcba9876543210fedcba98
OWNER_ID=153232337
APP_ID=777
LANE='{"login":"github-actions[bot]","id":41898282,"type":"Bot"}'
APP="{\"login\":\"melodic-automation-lanes[bot]\",\"id\":$APP_ID,\"type\":\"Bot\"}"
OWNER="{\"login\":\"owner\",\"id\":$OWNER_ID,\"type\":\"User\"}"
CODE_CHECK='pr-review / claude-review-status'
SEC_CHECK='pr-review-security / security-review'

event() { jq -cn --arg e "$1" --argjson actor "$2" --arg at "$3" '{event: $e, actor: $actor, created_at: $at, label: {name: "needs-human"}, performed_via_github_app: null}'; }
comment() { jq -cn --argjson user "$1" --arg at "$2" --arg body "$3" '{user: $user, created_at: $at, updated_at: $at, body: $body}'; }
note() { jq -cn --arg m "$1" --arg t "${2:-}" '{annotation_level: "notice", title: $t, message: $m}'; }
hold_note() { note "claude-lane-hold lane=claude-security-review sha=$1 criteria=${2:-critical-security} label=needs-human"; }
record() { note "claude-lane-review-complete lane=$1 sha=$2 findings=${3:-0} inline=${3:-0} scope=whole" claude-lane-review-complete; }
# job <id> <name> <completed_at> [status] [conclusion]
job() {
  jq -cn --argjson id "$1" --arg name "$2" --arg at "$3" --arg s "${4:-completed}" --arg c "${5:-success}" \
    '{id: $id, name: $name, run_attempt: 1, status: $s, conclusion: (if $c == "" then null else $c end), completed_at: (if $at == "" then null else $at end),
      steps: [{name: "Apply the hold", conclusion: "success"}]}'
}
# thread <severity> [resolved]: a security-lane thread.
thread() {
  jq -cn --arg s "$1" --argjson r "${2:-false}" '{isResolved: $r, isOutdated: $r, resolvedBy: null,
    comments: {nodes: [{author: {__typename: "Bot", login: "github-actions"}, createdAt: "2026-10-26T12:01:00Z",
      body: "Finding.\n\nseverity: \($s)\n\nclaude-lane: claude-security-review"}]}}'
}
threads() { STUB_THREADS="$(jq -cn --argjson n "[$1]" '{data: {repository: {pullRequest: {reviewThreads: {totalCount: ($n | length), nodes: $n}}}}}')"; export STUB_THREADS; }
# The security lane held OLD (run 20, job 201); both lanes reviewed HEAD (runs 10 and 21).
# head_notes <security-notes-at-HEAD> [security-job-at-HEAD]
head_notes() {
  STUB_NOTES="$(jq -cn --argjson a "[$(record claude-review "$HEAD")]" --argjson b "[$(record claude-security-review "$OLD" 1),$(hold_note "$OLD")]" \
    --argjson c "$1" '{"101": $a, "201": $b, "211": $c}')"
  STUB_JOBS="$(jq -cn --argjson a "$(job 101 "$CODE_CHECK" 2026-10-26T12:09:00Z)" --argjson b "$(job 201 "$SEC_CHECK" 2026-10-26T12:01:00Z)" \
    --argjson c "${2:-$(job 211 "$SEC_CHECK" 2026-10-26T12:10:00Z)}" '{"10": {jobs: [$a]}, "20": {jobs: [$b]}, "21": {jobs: [$c]}}')"
  export STUB_NOTES STUB_JOBS
}

reset() {
  export STUB_FAIL='' STUB_LABELS='needs-human' LANES_APP_ID="$APP_ID"
  export STUB_ACTORS="{\"actors\":[{\"kind\":\"human\",\"id\":$OWNER_ID}]}"
  export STUB_PR="{\"number\":6419,\"head\":{\"ref\":\"fix/sec\",\"sha\":\"$HEAD\"},\"base\":{\"ref\":\"main\"},\"body\":\"\"}"
  export STUB_DELETED='{"data":{"repository":{"pullRequest":{"timelineItems":{"filteredCount":0,"nodes":[]}}}}}'
  STUB_EVENTS="[$(event labeled "$LANE" 2026-10-26T12:00:30Z)]"
  STUB_COMMENTS="[$(comment "$LANE" 2026-10-26T12:00:40Z "<!-- claude-lane-hold lane=claude-security-review sha=$OLD criteria=critical-security -->
Held.

claude-lane: claude-security-review")]"
  STUB_RUNS="$(jq -cn --arg h "$HEAD" --arg o "$OLD" '{"pr-review-hosted.yml": {workflow_runs: [{id: 10, head_sha: $h, updated_at: "2026-10-26T12:09:10Z"}]},
    "pr-review-security-hosted.yml": {workflow_runs: [{id: 20, head_sha: $o, updated_at: "2026-10-26T12:01:10Z"}, {id: 21, head_sha: $h, updated_at: "2026-10-26T12:10:10Z"}]}}')"
  STUB_COMPARE="$(jq -cn --arg h "$HEAD" --arg o "$OLD" '{($h): {files: [{filename: "src/a.sh"}]}, ($o): {files: [{filename: "src/a.sh"}]}}')"
  export STUB_EVENTS STUB_COMMENTS STUB_RUNS STUB_COMPARE
  head_notes "[$(record claude-security-review "$HEAD")]"
  threads "$(thread CRITICAL true)"
  unset STUB_TRACKER
}

# expect <label> <want-cleared> <want-delete> <want-post> [want-out]
expect() {
  local label="$1" out rc cleared deleted posted config="$TMP_ROOT/base-config"
  : >"$TMP_ROOT/log"
  : >"$TMP_ROOT/output"
  rm -rf "$config" "$TMP_ROOT/lane-lift"
  mkdir -p "$config/.github/standards/trusted-actors" "$config/.github/scripts/pr-merge"
  [[ -z "${STUB_TRACKER+set}" ]] || printf '%s\n' "$STUB_TRACKER" >"$config/.work-item-tracker.json"
  printf '%s\n' "$STUB_ACTORS" >"$config/.github/standards/trusted-actors/trusted-actors.json"
  [[ " $STUB_FAIL " == *" module "* ]] || cp "$ROOT/.github/scripts/pr-merge/merge-holds.mjs" "$config/.github/scripts/pr-merge/"
  out="$(PATH="$TMP_ROOT/bin:$PATH" STUB_LOG="$TMP_ROOT/log" PR_NUMBER=6419 GITHUB_REPOSITORY=o/r \
    RUNNER_TEMP="$TMP_ROOT" GITHUB_OUTPUT="$TMP_ROOT/output" BASE_SHA="$BASE" HEAD_SHA="$HEAD" \
    BASE_CONFIG="$config" bash -e "$TMP_ROOT/body.sh" 2>&1)" && rc=0 || rc=$?
  cleared=no deleted=no posted=no
  grep -qxF 'cleared=true' "$TMP_ROOT/output" && cleared=yes
  grep -q -- '-X DELETE repos/o/r/issues/6419/labels/needs-human' "$TMP_ROOT/log" && deleted=yes
  grep -q -- '-X POST repos/o/r/issues/6419/comments' "$TMP_ROOT/log" && posted=yes
  if [[ "$rc" -ne 0 ]]; then
    fail "$label: the step must never fail the job, got rc=$rc out='$out'"
  elif [[ "$cleared" != "$2" || "$deleted" != "$3" || "$posted" != "$4" ]]; then
    fail "$label: cleared=$cleared deleted=$deleted posted=$posted, wanted $2/$3/$4; out='$out'"
  elif [[ -n "${5:-}" && "$out" != *"$5"* ]]; then
    fail "$label: output lacks '$5': '$out'"
  else
    ok "$label"
  fi
}

reset
expect "a clean re-review of a newer head lifts the lane's own hold" yes yes yes "reviewed $HEAD clean after holding $OLD"
post="$(sed -n '/-X POST/,/-X DELETE/p' "$TMP_ROOT/log" | grep -v -- '-X DELETE')"
if [[ "$post" == *"<!-- ci-status lane-hold-lifted held=$OLD head=$HEAD -->"* && "$post" == *"\`$OLD\`"* && "$post" == *"\`$HEAD\`"* && "$post" != *"claude-lane-hold"* ]]; then
  ok "the removal comment names both heads and is not itself a hold"
else
  fail "the removal comment: '$post'"
fi
if [[ "$(grep -n -- '-X POST' "$TMP_ROOT/log" | cut -d: -f1)" -lt "$(grep -n -- '-X DELETE' "$TMP_ROOT/log" | cut -d: -f1)" ]]; then
  ok "the comment is posted before the label comes off"
else
  fail "the label came off before the comment"
fi
if grep -q '/jobs?filter=all&per_page=100 --paginate$' "$TMP_ROOT/log" && grep -q '/annotations?per_page=100 --paginate$' "$TMP_ROOT/log"; then
  ok "the jobs and annotations reads take every page"
else
  fail "the jobs or annotations read is not paginated: '$(grep -E 'jobs|annotations' "$TMP_ROOT/log")'"
fi

# A re-run at the same head after the lift derives the lift again, so the
# hold-lift step stays skipped, and writes nothing.
reset
export STUB_LABELS=''
STUB_EVENTS="[$(event labeled "$LANE" 2026-10-26T12:00:30Z),$(event unlabeled "$LANE" 2026-10-26T12:11:00Z)]"
STUB_COMMENTS="$(jq -c --argjson c "$(comment "$LANE" 2026-10-26T12:11:00Z "<!-- ci-status lane-hold-lifted held=$OLD head=$HEAD -->
ci-status removed it.")" '. + [$c]' <<<"$STUB_COMMENTS")"
export STUB_EVENTS STUB_COMMENTS
expect "a re-run after the lift reads cleared and writes nothing" yes no no
export STUB_LABELS=needs-human
expect "a removal comment already posted is not posted again" yes yes no

reset
head_notes "[$(record claude-security-review "$HEAD" 1),$(hold_note "$HEAD")]"
expect "a hold at the current head keeps the label" no no no "holds the current head"
reset
STUB_RUNS="$(jq -cn --arg h "$HEAD" '{"pr-review-hosted.yml": {workflow_runs: [{id: 10, head_sha: $h, updated_at: "2026-10-26T12:09:10Z"}]},
  "pr-review-security-hosted.yml": {workflow_runs: [{id: 20, head_sha: $h, updated_at: "2026-10-26T12:01:10Z"}]}}')"
export STUB_RUNS
STUB_NOTES="$(jq -cn --argjson a "[$(record claude-review "$HEAD")]" --argjson b "[$(record claude-security-review "$HEAD" 1),$(hold_note "$HEAD")]" '{"101": $a, "201": $b}')"
export STUB_NOTES
expect "the head the lane held, with no newer review, keeps the label" no no no "holds the current head"

for severity in CRITICAL IMPORTANT; do
  reset
  threads "$(thread "$severity")"
  expect "an open $severity security finding at the new head keeps the label" no no no "open finding"
done
reset
threads "$(thread SUGGESTION)"
expect "an open SUGGESTION does not keep the label" yes yes yes

reset
STUB_EVENTS="[$(event labeled "$OWNER" 2026-10-26T12:00:30Z)]"
export STUB_EVENTS
expect "a label a person added keeps the label" no no no "someone other than a review lane"
STUB_EVENTS="[$(event labeled "$APP" 2026-10-26T12:00:30Z)]"
expect "a label the lanes App added for another reason keeps the label" no no no "someone other than a review lane"
STUB_EVENTS="[$(event labeled '{"login":"github-actions[bot]","id":9,"type":"Bot"}' 2026-10-26T12:00:30Z)]"
expect "a label by an account that only shares the bot login keeps the label" no no no "someone other than a review lane"
reset
STUB_COMMENTS="$(jq -c --argjson c "$(comment "$APP" 2026-10-26T12:05:00Z '<!-- work-items:escalation lane=pr-unblock kind=escalated -->')" '. + [$c]' <<<"$STUB_COMMENTS")"
export STUB_COMMENTS
expect "a lanes App escalation since the label keeps it" no no no "escalated"

reset
head_notes '[]'
expect "a review of the new head with no review record keeps the label" no no no "no complete review"
reset
head_notes '[]' "$(job 211 "$SEC_CHECK" '' in_progress '')"
expect "a review of the new head still going keeps the label" no no no "has not completed"
reset
head_notes "[$(record claude-security-review "$HEAD")]" "$(job 211 "$SEC_CHECK" 2026-10-26T12:10:00Z completed failure)"
expect "an errored review of the new head keeps the label" no no no "has not completed"

reset
STUB_COMPARE="$(jq -cn --arg h "$HEAD" --arg o "$OLD" '{($h): {files: [{filename: ".github/workflows/pr-review-security-hosted.yml"}]}, ($o): {files: []}}')"
export STUB_COMPARE
expect "a lane run on a head that changes a review-lane workflow keeps the label" no no no "changes a review-lane workflow"
reset
STUB_PR="$(jq -c --arg o "$OLD" '.head.sha = $o' <<<"$STUB_PR")"
export STUB_PR
expect "a pull request whose head moved since the event keeps the label" no no no "the head moved"
reset
STUB_EVENTS='[]'
export STUB_EVENTS
expect "a pull request that never carried the label stops after the events read" no no no "never added"
if [[ "$(grep -c '^api ' "$TMP_ROOT/log")" -eq 1 ]]; then ok "with no label event the events are the step's one read"; else fail "read more than the events: '$(cat "$TMP_ROOT/log")'"; fi
reset
export LANES_APP_ID=''
expect "an unset lanes App id keeps the label" no no no

for read in events pull comments deleted threads runs compare jobs notes module; do
  reset
  export STUB_FAIL="$read"
  expect "an unreadable $read read keeps the label" no no no
done
reset
export STUB_FAIL=labels
expect "an unreadable label list reports the lift and writes nothing" yes no no "::warning::could not read the labels"
reset
export STUB_FAIL=delete
expect "a failed label removal still reports the lift for the steps after it" yes yes yes "::warning::"

test_harness::report
