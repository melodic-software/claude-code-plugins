#!/usr/bin/env bash
# Runs the `Clear a cost-only review hold the owner decided` step body of
# .github/workflows/pr-require-checks.yml's ci-status under the shell Actions
# gives a step with no `shell:` (bash -e), against stub `gh` and `sleep`.
#
# A review lane's `cost` hold is cleared when every lane hold since a trusted
# person last removed the human-gated label is cost-only, and the pull request
# body cites the owner's unedited `**Decision recorded.** Cost:` comment on the
# pull request itself, or, newer than the pull request and naming it as
# `#<number>`, on its linked issue: the one issue GitHub records it as closing,
# else, when it closes none, the one plain `Refs:` issue (the base's
# merge-holds.mjs refsIssue). A second closing issue counts for nothing. The
# decision, the newest on the pull request else the newest on the issue,
# covers the head it decided (the sha of the newest cost hold notice a review
# lane's status job recorded before it, naming its own run's head; with none,
# no head) and a later head only when the net change against the base branch
# is the same at both (owner decisions Q17 c and Q18 d on #9436). The holds
# and the decided head are read from the lanes' check-run notices, never from
# a hold comment.
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
for env in 'BASE_SHA: ${{ github.event.pull_request.base.sha }}' 'HEAD_SHA: ${{ github.event.pull_request.head.sha }}' \
  "BASE_CONFIG: \${{ steps.base_config.outcome == 'success' && format('{0}/base-config', github.workspace) || '' }}"; do
  if [[ "$step" == *"$env"* ]]; then ok "step env carries $env"; else fail "step env lacks $env"; fi
done
order="$(grep -nE "^  ci-status:$|^      - name: ($NAME|Fail a pull request carrying the human-gated label|Fail a review-lane hold an untrusted account lifted)$" "$WORKFLOW" | cut -d: -f1 | paste -sd' ')"
read -r job_line cost_line gated_line lift_line <<<"$order"
if [[ -n "${lift_line:-}" && "$job_line" -lt "$cost_line" && "$cost_line" -lt "$gated_line" && "$gated_line" -lt "$lift_line" ]]; then
  ok "step sits in ci-status before the human-gated and hold-lift steps"
else
  fail "step is not inside ci-status before the human-gated step (lines: $order)"
fi
node_line="$(awk -v job="$job_line" 'NR > job && $0 == "      - name: Set up Node" { print NR; exit }' "$WORKFLOW")"
if [[ -n "$node_line" && "$job_line" -lt "$node_line" && "$node_line" -lt "$cost_line" ]] && grep -qxF '            /.github/scripts/pr-merge/merge-holds.mjs' "$WORKFLOW"; then
  ok "ci-status sets up the pinned Node and checks out the base merge-holds.mjs before the step runs refsIssue"
else
  fail "the step runs node with no pinned Node before it, or the base checkout lacks merge-holds.mjs (Set up Node line ${node_line:-none})"
fi
lift="$(awk '$0 == "      - name: Fail a review-lane hold an untrusted account lifted" { on = 1; next } on && /^        if: / { print; exit }' "$WORKFLOW")"
if [[ "$lift" == *"steps.cost_hold.outputs.cleared != 'true'"* ]]; then
  ok "the hold-lift step does not run once a recorded decision clears the hold"
else
  fail "the hold-lift step does not read cost_hold's cleared output: '$lift'"
fi

# The stub logs its arguments and answers from STUB_* variables; a read whose
# name is in STUB_FAIL fails. The base commit's config is a fixture directory:
# STUB_TRACKER (absent when unset) and STUB_ACTORS; a `tracker` failure leaves
# BASE_CONFIG empty, as a failed checkout does, and an `actors` failure leaves
# the trusted-actor list out of it. Runs, jobs and annotations come from JSON maps
# keyed by workflow file, run id and check-run id.
mkdir -p "$TMP_ROOT/bin"
cat >"$TMP_ROOT/bin/gh" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$STUB_LOG"
failing() { [[ " ${STUB_FAIL:-} " == *" $1 "* ]] && exit 1; return 0; }
from() { jq -ce --arg k "$2" '.[$k] // error' <<<"$1" || { echo 'gh: Not Found (HTTP 404)' >&2; exit 1; }; }
# The path segment after /<1>/ in the api path argument.
key() { local a; for a in "${@:2}"; do [[ "$a" == */"$1"/* ]] && { a="${a##*/"$1"/}"; printf '%s' "${a%%[/?]*}"; return; }; done; }
case "$*" in
*'-X DELETE'*/labels/*) failing delete ;;
*/issues/6419/labels*) failing labels; [[ -z "$STUB_LABELS" ]] || tr ',' '\n' <<<"$STUB_LABELS" ;;
*/issues/6419/events*) failing events; printf '%s\n' "$STUB_EVENTS" ;;
*'-X POST'*/issues/6419/comments*) failing post ;;
*/issues/6419/comments*) failing comments; printf '%s\n' "$STUB_COMMENTS" ;;
*/issues/comments/*) failing decision; from "$STUB_DECISIONS" "$(key comments "$@")" ;;
*/issues/[0-9]*) failing issue; from "$STUB_ISSUES" "$(key issues "$@")" ;;
*/actions/workflows/*/runs*)
  failing runs
  [[ "$*" == *'branch=fix%2Fcost&'* ]] || exit 1
  from "$STUB_RUNS" "$(key workflows "$@")"
  ;;
*/compare/"$BASE_SHA..."*) failing compare; args="$*"; from "$STUB_COMPARE" "${args##*...}" ;;
*/compare/"${STUB_BASE_REF:-main}..."*) failing compare; args="$*"; from "$STUB_COMPARE" "${args##*...}" ;;
*/actions/runs/*/jobs*) failing jobs; from "$STUB_JOBS" "$(key runs "$@")" ;;
*/check-runs/*/annotations*) failing notes; from "$STUB_NOTES" "$(key check-runs "$@")" ;;
*/pulls/6419*) failing pull; printf '%s\n' "$STUB_PR" ;;
*graphql*COMMENT_DELETED_EVENT*) failing deleted; printf '%s\n' "$STUB_DELETED" ;;
*graphql*closingIssuesReferences*) failing closing; printf '%s\n' "$STUB_CLOSING" ;;
*graphql*lastEditedAt*) failing edited; printf '%s\n' "$STUB_EDITED" ;;
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
LINK='https://github.com/o/r/issues/9306#issuecomment-111'
LANE='{"login":"github-actions[bot]","id":41898282,"type":"Bot"}'
APP="{\"login\":\"melodic-automation-lanes[bot]\",\"id\":$APP_ID,\"type\":\"Bot\"}"
OWNER="{\"login\":\"owner\",\"id\":$OWNER_ID,\"type\":\"User\"}"
STRANGER='{"login":"someone","id":42,"type":"User"}'
CODE_CHECK='pr-review / claude-review-status'
SEC_CHECK='pr-review-security / security-review'

event() { jq -cn --arg e "$1" --argjson actor "$2" --arg at "$3" '{event: $e, actor: $actor, created_at: $at, label: {name: "needs-human"}}'; }
comment() { jq -cn --argjson user "$1" --arg at "$2" --arg body "$3" '{user: $user, created_at: $at, updated_at: $at, body: $body}'; }
decision() {
  jq -cn --arg url "https://api.github.com/repos/o/r/issues/$1" --argjson user "$2" --arg at "$3" --arg body "$4" \
    '{issue_url: $url, user: $user, performed_via_github_app: null, created_at: $at, body: $body, node_id: "IC_1"}'
}
note() { jq -cn --arg m "$1" '{annotation_level: "notice", message: $m}'; }
hold_note() { note "claude-lane-hold lane=${2:-claude-review} sha=$HEAD criteria=$1 label=needs-human"; }
# marker <sha> [at]: a review lane's hold comment on the pull request, which
# decides no head.
marker() {
  comment "$LANE" "${2:-2026-10-23T13:10:00Z}" "<!-- claude-lane-hold lane=claude-review sha=$1 criteria=cost -->
Held for a person."
}
TF='{"filename":"infra/main.tf","status":"modified","patch":"@@ -1 +1 @@\n-a\n+b"}'
MORE='{"filename":"scripts/run.sh","status":"modified","patch":"+y"}'
# nets <old-files> <head-files>: the compare answers at OLD and HEAD.
nets() { STUB_COMPARE="$(jq -cn --arg h "$HEAD" --arg o "$OLD" --argjson a "$1" --argjson b "$2" '{($o): {files: $a}, ($h): {files: $b}}')"; export STUB_COMPARE; }
# job <id> <name> <completed_at>
job() { jq -cn --argjson id "$1" --arg name "$2" --arg at "$3" '{id: $id, name: $name, completed_at: $at}'; }
# lanes <code-notes> <security-notes>: one run per lane, its status job done
# at 13:20:30 and 13:21:00, and the decided run (decided "$HEAD").
lanes() {
  STUB_RUNS="$(jq -c . <<<'{"pr-review-hosted.yml":{"workflow_runs":[{"id":1,"head_sha":"0123456789abcdef0123456789abcdef01234567","created_at":"2026-10-23T13:19:00Z","updated_at":"2026-10-23T13:20:40Z","head_repository":{"full_name":"o/r"}}]},"pr-review-security-hosted.yml":{"workflow_runs":[{"id":2,"head_sha":"0123456789abcdef0123456789abcdef01234567","created_at":"2026-10-23T13:19:30Z","updated_at":"2026-10-23T13:21:10Z","head_repository":{"full_name":"o/r"}}]}}')"
  STUB_JOBS="$(jq -cn --argjson a "$(job 11 "$CODE_CHECK" 2026-10-23T13:20:30Z)" --argjson b "$(job 21 "$SEC_CHECK" 2026-10-23T13:21:00Z)" \
    '{"1": {jobs: [{id: 10, name: "kill-switch", completed_at: "2026-10-23T13:19:00Z"}, $a]}, "2": {jobs: [$b]}}')"
  STUB_NOTES="$(jq -cn --argjson a "$1" --argjson b "$2" '{"11": $a, "21": $b, "10": []}')"
  STUB_COMPARE="$(jq -cn --arg h "$HEAD" --arg o "$OLD" '{($h): {files: [{filename: "README.md"}]}, ($o): {files: []}}')"
  export STUB_RUNS STUB_JOBS STUB_NOTES STUB_COMPARE
  nodecided
  decided "$HEAD"
}
# decided <sha> [completed_at] [criteria] [workflow] [job] [notice-sha]: a run
# on <sha>, started at 13:00, whose job (the code lane's status job unless
# named) recorded a hold notice naming [notice-sha] (default <sha>).
decided() {
  local id=$((DECIDED += 1)) at="${2:-2026-10-23T13:10:00Z}"
  STUB_RUNS="$(jq -c --arg f "${4:-pr-review-hosted.yml}" --argjson id "$id" --arg sha "$1" --arg at "$at" \
    '.[$f].workflow_runs += [{id: $id, head_sha: $sha, created_at: "2026-10-23T13:00:00Z", updated_at: $at, head_repository: {full_name: "o/r"}}]' <<<"$STUB_RUNS")"
  STUB_JOBS="$(jq -c --arg id "$id" --argjson j "$(job "$id" "${5:-$CODE_CHECK}" "$at")" '. + {($id): {jobs: [$j]}}' <<<"$STUB_JOBS")"
  STUB_NOTES="$(jq -c --arg id "$id" --argjson n "[$(note "claude-lane-hold lane=claude-review sha=${6:-$1} criteria=${3:-cost} label=needs-human")]" \
    '. + {($id): $n}' <<<"$STUB_NOTES")"
  export STUB_RUNS STUB_JOBS STUB_NOTES
}
# nodecided: drops every run decided added.
nodecided() {
  DECIDED=100
  STUB_RUNS="$(jq -c 'map_values(.workflow_runs |= map(select(.id <= 100)))' <<<"$STUB_RUNS")"
  export STUB_RUNS
}

reset() {
  export STUB_FAIL='' STUB_LABELS='needs-human' LANES_APP_ID="$APP_ID"
  export STUB_ACTORS="{\"actors\":[{\"kind\":\"human\",\"id\":$OWNER_ID},{\"kind\":\"bot\",\"id\":5}]}"
  export STUB_PR="{\"number\":6419,\"created_at\":\"2026-10-23T05:00:00Z\",\"head\":{\"ref\":\"fix/cost\",\"sha\":\"0123456789abcdef0123456789abcdef01234567\"},\"base\":{\"ref\":\"main\"},\"body\":\"Closes #9306\\n\\n- Cost decision: [Q50]($LINK)\"}"
  export STUB_CLOSING='{"data":{"repository":{"pullRequest":{"closingIssuesReferences":{"totalCount":1,"nodes":[{"number":9306,"repository":{"nameWithOwner":"o/r"}}]}}}}}'
  STUB_DECISIONS="$(jq -cn --argjson c "$(decision 9306 "$OWNER" 2026-10-23T13:14:57Z '**Decision recorded.** Cost: accepted for #6419.')" '{"111": $c}')"
  export STUB_DECISIONS
  export STUB_EDITED='{"data":{"node":{"lastEditedAt":null}}}'
  export STUB_ISSUES='{"9306":{"number":9306}}'
  export STUB_DELETED='{"data":{"repository":{"pullRequest":{"timelineItems":{"filteredCount":0,"nodes":[]}}}}}'
  STUB_EVENTS="[$(event labeled "$LANE" 2026-10-23T13:20:20Z)]"
  STUB_COMMENTS="[$(comment "$OWNER" 2026-10-23T05:40:00Z 'A comment.')]"
  export STUB_EVENTS STUB_COMMENTS
  lanes "[$(hold_note cost),$(note "claude-lane-review-complete lane=claude-review sha=$HEAD findings=0")]" '[]'
  unset STUB_TRACKER
}
# The owner lifted an earlier hold at 13:15, so the 05:39 escalation is outside the window.
lifted() {
  STUB_EVENTS="[$(event labeled "$APP" 2026-10-23T05:39:30Z),$(event unlabeled "$OWNER" 2026-10-23T13:15:00Z),$(event labeled "$LANE" 2026-10-23T13:20:20Z)]"
  STUB_COMMENTS="[$(comment "$APP" 2026-10-23T05:39:35Z '<!-- work-items:escalation lane=pr-unblock kind=escalated -->')]"
  export STUB_EVENTS STUB_COMMENTS
}

# expect <label> <want-cleared: yes|no> <want-delete: yes|no> <want-post: yes|no> [want-out]
expect() {
  local label="$1" out rc cleared deleted posted config="$TMP_ROOT/base-config"
  : >"$TMP_ROOT/log"
  : >"$TMP_ROOT/output"
  rm -rf "$config"
  mkdir -p "$config/.github/standards/trusted-actors"
  [[ -z "${STUB_TRACKER+set}" ]] || printf '%s\n' "$STUB_TRACKER" >"$config/.work-item-tracker.json"
  [[ " $STUB_FAIL " == *" actors "* ]] || printf '%s\n' "$STUB_ACTORS" >"$config/.github/standards/trusted-actors/trusted-actors.json"
  mkdir -p "$config/.github/scripts/pr-merge"
  [[ " $STUB_FAIL " == *" module "* ]] || cp "$ROOT/.github/scripts/pr-merge/merge-holds.mjs" "$config/.github/scripts/pr-merge/"
  [[ " $STUB_FAIL " != *" tracker "* ]] || config=
  out="$(PATH="$TMP_ROOT/bin:$PATH" STUB_LOG="$TMP_ROOT/log" PR_NUMBER=6419 GITHUB_REPOSITORY=o/r \
    RUNNER_TEMP="$TMP_ROOT" GITHUB_OUTPUT="$TMP_ROOT/output" BASE_SHA="$BASE" HEAD_SHA="$HEAD" \
    BASE_CONFIG="$config" bash -e "$TMP_ROOT/body.sh" 2>&1)" && rc=0 || rc=$?
  cleared=no deleted=no posted=no
  grep -qxF 'cleared=true' "$TMP_ROOT/output" && cleared=yes
  grep -q -- '-X DELETE repos/o/r/issues/6419/labels/needs-human' "$TMP_ROOT/log" && deleted=yes
  grep -q -- '-X POST repos/o/r/issues/6419/comments' "$TMP_ROOT/log" && posted=yes
  if [[ "$rc" -ne 0 ]]; then
    fail "$label: the step must never fail the job, got rc=$rc out='$out'"
  elif grep -q '/contents/' "$TMP_ROOT/log"; then
    fail "$label: the base config was read through the API: '$(grep '/contents/' "$TMP_ROOT/log")'"
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
if grep -q '/jobs?filter=all&per_page=100 --paginate$' "$TMP_ROOT/log" && grep -q '/annotations?per_page=100 --paginate$' "$TMP_ROOT/log"; then
  ok "the jobs and annotations reads take every page, so a hold notice on page two is seen"
else
  fail "the jobs or annotations read is not paginated: '$(grep -E 'jobs|annotations' "$TMP_ROOT/log")'"
fi
if [[ "$(grep -n -- '-X POST' "$TMP_ROOT/log" | cut -d: -f1)" -lt "$(grep -n -- '-X DELETE' "$TMP_ROOT/log" | cut -d: -f1)" ]]; then
  ok "the comment is posted before the label comes off"
else
  fail "the label came off before the comment"
fi

reset
STUB_COMMENTS="[$(comment "$LANE" 2026-10-23T13:21:00Z '<!-- ci-status cost-hold-cleared decision=111 -->
ci-status took it off.')]"
expect "a decision already cited in a removal comment is not cited again" yes yes no
STUB_COMMENTS="[$(comment "$STRANGER" 2026-10-23T13:21:00Z '<!-- ci-status cost-hold-cleared decision=111 -->')]"
expect "a removal comment by a person does not count as posted" yes yes yes
reset
export STUB_LABELS=''
expect "with the label already off the hold reads cleared and nothing is written" yes no no

reset
STUB_PR='{"number":6419,"created_at":"2026-10-23T05:00:00Z","head":{"ref":"fix/cost","sha":"0123456789abcdef0123456789abcdef01234567"},"body":"Closes #9306"}'
expect "no decision cited in the body clears nothing" no no no
if grep -qE 'actions/workflows|check-runs|graphql' "$TMP_ROOT/log"; then
  fail "with no link in the body the step read runs or GraphQL"
else
  ok "with no link in the body the step stops before the run and GraphQL reads"
fi
STUB_PR="{\"number\":6419,\"created_at\":\"2026-10-23T05:00:00Z\",\"head\":{\"ref\":\"fix/cost\",\"sha\":\"0123456789abcdef0123456789abcdef01234567\"},\"body\":\"<!-- $LINK -->\"}"
expect "a decision cited only inside an HTML comment clears nothing" no no no
STUB_PR="{\"number\":6419,\"created_at\":\"2026-10-23T05:00:00Z\",\"head\":{\"ref\":\"fix/cost\",\"sha\":\"0123456789abcdef0123456789abcdef01234567\"},\"body\":\"<!-- unclosed $LINK\"}"
expect "a decision cited inside an unclosed HTML comment clears nothing" no no no
STUB_PR='{"number":6419,"created_at":"2026-10-23T05:00:00Z","head":{"ref":"fix/cost","sha":"0123456789abcdef0123456789abcdef01234567"},"body":"https://github.com/x/r/issues/9306#issuecomment-111"}'
expect "a link to another repository clears nothing" no no no
STUB_PR='{"number":6419,"created_at":"2026-10-23T05:00:00Z","head":{"ref":"fix/cost","sha":"0123456789abcdef0123456789abcdef01234567"},"body":"https://github.com/o/r/issues/77#issuecomment-111"}'
expect "a link to an issue that does not close the pull request clears nothing" no no no

reset
STUB_DECISIONS="$(jq -cn --argjson c "$(decision 9306 "$OWNER" 2026-10-23T04:00:00Z '**Decision recorded.** Cost: accepted for #6419.')" '{"111": $c}')"
expect "an issue decision older than the pull request clears nothing" no no no
STUB_DECISIONS="$(jq -cn --argjson c "$(decision 6419 "$OWNER" 2026-10-23T04:00:00Z '**Decision recorded.** Cost: accepted.')" '{"111": $c}')"
STUB_PR='{"number":6419,"created_at":"2026-10-23T05:00:00Z","head":{"ref":"fix/cost","sha":"0123456789abcdef0123456789abcdef01234567"},"base":{"ref":"main"},"body":"https://github.com/o/r/pull/6419#issuecomment-111"}'
nodecided
decided "$HEAD" 2026-10-23T03:00:00Z
WANT_LINK=https://github.com/o/r/pull/6419#issuecomment-111 expect "a decision on the pull request itself clears the hold" yes yes yes
nodecided
decided "$HEAD"
expect "with no cost hold notice before the decision nothing carries, even at the same head" no no no "covering this head"
reset
STUB_DECISIONS="$(jq -cn --argjson c "$(decision 9306 "$STRANGER" 2026-10-23T13:14:57Z '**Decision recorded.** Cost: accepted for #6419.')" '{"111": $c}')"
expect "a decision by someone off the trusted-actor list clears nothing" no no no
STUB_DECISIONS="$(jq -cn --argjson c "$(decision 9306 "$OWNER" 2026-10-23T13:14:57Z '**Decision recorded.** Trust: accepted for #6419.')" '{"111": $c}')"
expect "a decision recorded for something other than cost clears nothing" no no no
STUB_DECISIONS="$(jq -cn --argjson c "$(decision 9306 "$OWNER" 2026-10-23T13:14:57Z '**Decision recorded.** Cost: accepted for #6419.')" '{"111": ($c | .performed_via_github_app = {slug: "x"})}')"
expect "a decision posted through an App clears nothing" no no no
reset
export STUB_EDITED='{"data":{"node":{"lastEditedAt":"2026-10-23T13:30:00Z"}}}'
expect "an edited decision clears nothing" no no no
reset
export STUB_CLOSING='{"data":{"repository":{"pullRequest":{"closingIssuesReferences":{"totalCount":2,"nodes":[{"number":9306,"repository":{"nameWithOwner":"o/r"}},{"number":9307,"repository":{"nameWithOwner":"o/r"}}]}}}}}'
expect "a decision on one of two closing issues clears nothing" no no no
export STUB_CLOSING='{"data":{"repository":{"pullRequest":{"closingIssuesReferences":{"totalCount":1,"nodes":[{"number":9306,"repository":{"nameWithOwner":"x/r"}}]}}}}}'
expect "a closing issue in another repository clears nothing" no no no
# The exploit: the owner records a cost decision on an unrelated issue, and the
# author points the body at it. Only GitHub's closing references count.
export STUB_CLOSING='{"data":{"repository":{"pullRequest":{"closingIssuesReferences":{"totalCount":1,"nodes":[{"number":8890,"repository":{"nameWithOwner":"o/r"}}]}}}}}'
STUB_PR="{\"number\":6419,\"created_at\":\"2026-10-23T05:00:00Z\",\"head\":{\"ref\":\"fix/cost\",\"sha\":\"0123456789abcdef0123456789abcdef01234567\"},\"body\":\"Closes #8890\\nRefs: #9306\\n\\n- Cost decision: [Q50]($LINK)\"}"
expect "a decision on an unrelated issue the body names on a Refs line clears nothing" no no no
export STUB_CLOSING='{"data":{"repository":{"pullRequest":{"closingIssuesReferences":{"totalCount":0,"nodes":[]}}}}}'
STUB_PR="{\"number\":6419,\"created_at\":\"2026-10-23T05:00:00Z\",\"head\":{\"ref\":\"fix/cost\",\"sha\":\"0123456789abcdef0123456789abcdef01234567\"},\"body\":\"Closes #9306\\n\\n- Cost decision: [Q50]($LINK)\"}"
expect "a Closes line GitHub does not record as closing clears nothing" no no no

# A decision binds to one pull request: one on the linked issue counts only
# when it names the pull request, and with no closing issue the linked issue is the one
# plain Refs: issue.
with_body() {
  STUB_PR="$(jq -cn --arg body "$1" '{number: 6419, created_at: "2026-10-23T05:00:00Z", head: {ref: "fix/cost", sha: "0123456789abcdef0123456789abcdef01234567"}, body: $body}')"
  export STUB_PR
}
says() {
  STUB_DECISIONS="$(jq -cn --argjson c "$(decision 9306 "${2:-$OWNER}" 2026-10-23T13:14:57Z "**Decision recorded.** Cost: $1")" '{"111": $c}')"
  export STUB_DECISIONS
}
reset
says 'accepted for another change.'
expect "a closing-issue decision that names no pull request clears nothing" no no no
for text in 'accepted for #64190.' 'accepted for #641.' 'accepted for x/r#6419.' 'accepted for pull 6419.' 'accepted for &#6419;' 'accepted for ##6419.'; do
  says "$text"
  expect "a closing-issue decision reading '$text' clears nothing" no no no
done
says 'accepted (#6419)'
expect "a closing-issue decision naming (#6419) clears the hold" yes yes yes
reset
export STUB_CLOSING='{"data":{"repository":{"pullRequest":{"closingIssuesReferences":{"totalCount":0,"nodes":[]}}}}}'
with_body "Refs: #9306

- Cost decision: [Q50]($LINK)"
expect "a Refs-issue decision naming the pull request clears the hold" yes yes yes
says 'accepted.'
expect "a Refs-issue decision that names no pull request clears nothing" no no no
says 'accepted for #6419.' "$STRANGER"
expect "a Refs-issue decision naming the pull request by someone off the list clears nothing" no no no
says 'accepted for #6419.'
export STUB_FAIL=module
expect "an unreadable base merge-holds.mjs clears nothing" no no no "the Refs line could not be read"
export STUB_FAIL=issue
expect "an unreadable Refs issue clears nothing" no no no "the Refs issue is unreadable"
export STUB_FAIL=''
export STUB_ISSUES='{"9306":{"number":9306,"pull_request":{"url":"x"}}}'
expect "a Refs number that names a pull request consults no issue and clears nothing" no no no
export STUB_ISSUES='{"9306":{"number":9306}}'
for body in "Refs: #9306
Refs: #9307" "Refs: #9306, #9307" '```
Refs: #9306
```' '<!-- Refs: #9306 -->' 'refs #9306'; do
  with_body "$body

- Cost decision: [Q50]($LINK)"
  expect "a body whose Refs lines read '${body//$'\n'/ }' names no linked issue and clears nothing" no no no
done

# The carry rule (#9436 Q18 d): the decided head is OLD, the current HEAD.
reset
nodecided
decided "$OLD"
nets "[$TF]" "[$TF]"
expect "a base merge after the decided head carries the decision" yes yes yes
if grep -q "compare/main...$OLD" "$TMP_ROOT/log"; then ok "the decided head's net change is read against the base branch"; else fail "no compare at the decided head"; fi
nets "[$TF]" "[$TF,$MORE]"
expect "a pull request commit after the decided head clears nothing" no no no "covering this head"
nets "[$TF,$MORE]" "[$MORE,$TF]"
expect "a rebase with the same net change, in another file order, carries the decision" yes yes yes
nets "[$TF,$MORE]" "[$TF]"
expect "a rebase that drops one of its files clears nothing" no no no "covering this head"
nets "[$TF]" "[$(jq -c '.patch = "@@ -1 +1 @@\n-a\n+c"' <<<"$TF")]"
expect "a conflict resolution that changes the net change clears nothing" no no no "covering this head"
nets "[$TF]" "[$(jq -c '.status = "renamed" | .previous_filename = "infra/old.tf"' <<<"$TF")]"
expect "a rename since the decided head clears nothing" no no no "covering this head"
nets "$(jq -cn '[range(299) | {filename: "f\(.)", status: "added", patch: "+x"}]')" "$(jq -cn '[range(299) | {filename: "f\(.)", status: "added", patch: "+x"}]')"
expect "a net change of 299 files carries the decision" yes yes yes
nets "$(jq -cn '[range(300) | {filename: "f\(.)", status: "added", patch: "+x"}]')" "$(jq -cn '[range(300) | {filename: "f\(.)", status: "added", patch: "+x"}]')"
expect "a compare of 300 files carries nothing" no no no
nets '[{"filename":"a.png","status":"modified"}]' '[{"filename":"a.png","status":"modified"}]'
expect "a file with no patch carries nothing" no no no "covering this head"
nets "[$TF]" "[$TF]"
export STUB_FAIL=compare
expect "a failed compare read carries nothing" no no no "are unreadable"
export STUB_FAIL=''
nodecided
decided "$HEAD" 2026-10-23T13:00:00Z
decided "$OLD" 2026-10-23T13:12:00Z
nets "[$TF]" "[$TF,$MORE]"
expect "the latest notice before the decision decides its head, not an older one at the head" no no no "covering this head"
nodecided
decided "$OLD" 2026-10-23T13:00:00Z
decided "$HEAD" 2026-10-23T13:12:00Z cost,trust-gate
lifted
expect "a later notice before the decision whose criteria include cost decides its head" yes yes yes
nodecided
decided "$OLD"
decided "$HEAD" 2026-10-23T13:16:00Z
expect "a notice after the decision decides nothing" no no no "covering this head"
nodecided
decided "$OLD"
decided "$HEAD" 2026-10-23T13:12:00Z trust-gate
expect "a later notice without cost decides nothing, so the older cost notice does" no no no "covering this head"
nodecided
decided "$OLD" 2026-10-23T13:12:00Z cost pr-review-hosted.yml "$CODE_CHECK" "$HEAD"
expect "a notice naming a head its run did not run on decides nothing" no no no "covering this head"
# A run on a same-named branch of another repository (a fork pull request)
# speaks for that pull request, not this one.
for head_repo in '{"full_name":"f/r"}' null; do
  nodecided
  decided "$OLD"
  decided "$HEAD" 2026-10-23T13:12:00Z
  nets "[$TF]" "[$TF,$MORE]"
  STUB_RUNS="$(jq -c --argjson r "$head_repo" '.["pr-review-hosted.yml"].workflow_runs |= map(if .id == 102 then .head_repository = $r else . end)' <<<"$STUB_RUNS")"
  export STUB_RUNS
  expect "a notice from a run whose head repository is $head_repo decides nothing" no no no "covering this head"
done
nodecided
decided "$HEAD" 2026-10-23T13:12:00Z cost pr-review-hosted.yml 'pr-review / review-key'
expect "a notice from a job other than the lane's status job decides nothing" no no no "covering this head"
nodecided
decided "$HEAD" 2026-10-23T13:12:00Z cost pr-review-hosted.yml "$SEC_CHECK"
expect "a notice under the other lane's status job name in this lane's workflow decides nothing" no no no "covering this head"
nodecided
decided "$HEAD" 2026-10-23T13:12:00Z cost pr-review-security-hosted.yml "$SEC_CHECK"
expect "a cost notice from the security lane's status job decides its head" yes yes yes
nodecided
decided "$HEAD" 2026-10-23T13:12:00Z
decided "$OLD" 2026-10-23T13:12:00Z cost pr-review-security-hosted.yml "$SEC_CHECK"
expect "two heads noticed at the newest time decide nothing" no no no "covering this head"
nodecided
STUB_COMMENTS="[$(marker "$HEAD" 2026-10-23T13:12:00Z)]"
expect "a github-actions[bot] hold comment with no notice decides no head" no no no "covering this head"
reset
STUB_COMMENTS="[$(marker "$OLD" 2026-10-23T13:12:00Z)]"
expect "a newer hold comment naming another head does not move the decided head" yes yes yes
reset
nodecided
decided "$OLD"
STUB_COMPARE="$(jq -cn --arg o "$OLD" --arg h "$HEAD" '{($o): {files: [{filename: ".github/workflows/pr-review-hosted.yml"}]}, ($h): {files: []}}')"
expect "a run before the decision on a head that changes a review-lane workflow keeps the hold" no no no "changes a review-lane workflow"
reset
nodecided
STUB_RUNS="$(jq -c --arg o "$OLD" '.["pr-review-hosted.yml"].workflow_runs += [{id: 5, head_sha: $o, created_at: "2026-10-23T13:16:00Z", updated_at: "2026-10-23T13:17:00Z", head_repository: {full_name: "o/r"}}]' <<<"$STUB_RUNS")"
STUB_JOBS="$(jq -c --argjson j "$(job 5 "$CODE_CHECK" 2026-10-23T13:12:00Z)" '. + {"5": {jobs: [$j]}}' <<<"$STUB_JOBS")"
STUB_NOTES="$(jq -c --argjson n "[$(hold_note cost)]" '. + {"5": $n}' <<<"$STUB_NOTES")"
STUB_EVENTS="[$(event unlabeled "$OWNER" 2026-10-23T13:18:00Z),$(event labeled "$LANE" 2026-10-23T13:20:20Z)]"
export STUB_RUNS STUB_JOBS STUB_NOTES STUB_EVENTS
expect "with only a run started after the decision and outside the window, nothing carries" no no no "covering this head"
if grep -q 'actions/runs/5/jobs' "$TMP_ROOT/log"; then fail "a run started after the decision was read for the decided head"; else ok "a run started after the decision is not read for the decided head"; fi
nodecided
STUB_COMMENTS='[]'
expect "an issue decision with no notice before it clears nothing" no no no "covering this head"
reset
nodecided
decided "$OLD"
nets "[$TF]" "[$TF]"
export STUB_FAIL=module
expect "an unreadable base merge-holds.mjs carries no closing-issue decision" no no no "covering this head"
reset
expect "at the decided head the decision carries" yes yes yes
if grep -q 'compare/main\.\.\.' "$TMP_ROOT/log"; then fail "a decision at its own head read a compare"; else ok "a decision at its own head reads no compare"; fi
nodecided
decided "$OLD"
nets "[$TF,$TF]" "[$TF,$TF]"
expect "a filename listed twice carries nothing" no no no "covering this head"
nets '[{"filename":"b.tf","status":"renamed","previous_filename":"a.tf"}]' '[{"filename":"b.tf","status":"renamed","previous_filename":"a.tf"}]'
expect "a patchless pure rename carries nothing" no no no "covering this head"
nets "[$TF]" "[$TF]"
for base in '-main' 'a..b' 'a b' ''; do
  STUB_PR="$(jq -c --arg b "$base" '.base.ref = $b' <<<"$STUB_PR")"
  expect "a base branch named '$base' carries nothing" no no no "covering this head"
  if grep -q '/compare/[^0-9]' "$TMP_ROOT/log"; then fail "an unusable base name '$base' was compared"; else ok "an unusable base name '$base' is never compared"; fi
done
STUB_PR="$(jq -c '.base.ref = "release/2.x"' <<<"$STUB_PR")"
STUB_BASE_REF=release/2.x expect "a base merge on a base branch with a slash carries" yes yes yes
# The decision is the newest on the pull request, else the newest on the issue.
reset
PULL_LINK=https://github.com/o/r/pull/6419#issuecomment
STUB_PR="$(jq -c --arg body "Closes #9306
$LINK
$PULL_LINK-112
$PULL_LINK-113" '.body = $body' <<<"$STUB_PR")"
STUB_DECISIONS="$(jq -cn --argjson a "$(decision 9306 "$OWNER" 2026-10-23T13:14:57Z '**Decision recorded.** Cost: accepted for #6419.')" \
  --argjson b "$(decision 6419 "$OWNER" 2026-10-23T13:00:00Z '**Decision recorded.** Cost: accepted.')" \
  --argjson c "$(decision 6419 "$OWNER" 2026-10-23T13:12:00Z '**Decision recorded.** Cost: accepted.')" '{"111": $a, "112": $b, "113": $c}')"
export STUB_DECISIONS
nodecided
decided "$HEAD" 2026-10-23T13:11:00Z
WANT_LINK=$PULL_LINK-113 expect "the newest decision on the pull request is judged over a newer one on the issue" yes yes yes
nodecided
decided "$HEAD" 2026-10-23T12:00:00Z
decided "$OLD" 2026-10-23T13:11:00Z
nets "[$TF]" "[$TF,$MORE]"
expect "only the chosen decision may carry, so an older one at this head does not" no no no "covering this head"

reset
lanes "[$(hold_note cost,trust-gate)]" '[]'
expect "a hold with cost and trust-gate clears nothing" no no no "is not cost-only"
lanes "[$(hold_note cost)]" "[$(hold_note critical-security claude-security-review)]"
expect "a critical-security hold from the other lane clears nothing" no no no "is not cost-only"
STUB_COMMENTS="[$(comment "$LANE" 2026-10-23T13:21:01Z "<!-- claude-lane-hold lane=claude-security-review sha=$HEAD criteria=cost -->
claude-lane: claude-security-review")]"
expect "a hold comment edited to read cost does not outweigh the lane's notice" no no no "is not cost-only"
reset
lanes "[$(note "claude-lane-hold lane=claude-review sha=$HEAD label=needs-human")]" '[]'
expect "a hold notice with no criteria clears nothing" no no no "is not cost-only"
reset
STUB_JOBS="$(jq -cn --argjson a "$(job 11 "$CODE_CHECK" 2026-10-23T13:20:30Z)" --argjson c "$(job 12 "$CODE_CHECK" 2026-10-23T13:25:00Z)" \
  --argjson b "$(job 21 "$SEC_CHECK" 2026-10-23T13:21:00Z)" '{"1": {jobs: [$a, $c]}, "2": {jobs: [$b]}}')"
STUB_NOTES="$(jq -cn --argjson a "[$(hold_note cost)]" --argjson c "[$(hold_note trust-gate)]" '{"11": $a, "12": $c, "21": []}')"
export STUB_JOBS STUB_NOTES
nodecided
decided "$HEAD"
expect "a re-run attempt that held for trust-gate clears nothing" no no no "is not cost-only"

reset
STUB_RUNS="$(jq -c . <<<'{"pr-review-hosted.yml":{"workflow_runs":[{"id":1,"head_sha":"0123456789abcdef0123456789abcdef01234567","created_at":"2026-10-23T13:19:00Z","updated_at":"2026-10-23T13:20:40Z","head_repository":{"full_name":"o/r"}},{"id":3,"head_sha":"fedcba9876543210fedcba9876543210fedcba98","created_at":"2026-10-23T13:09:00Z","updated_at":"2026-10-23T13:10:10Z","head_repository":{"full_name":"o/r"}}]},"pr-review-security-hosted.yml":{"workflow_runs":[{"id":2,"head_sha":"0123456789abcdef0123456789abcdef01234567","created_at":"2026-10-23T13:19:30Z","updated_at":"2026-10-23T13:21:10Z","head_repository":{"full_name":"o/r"}}]}}')"
STUB_JOBS="$(jq -c --argjson c "$(job 31 "$CODE_CHECK" 2026-10-23T13:10:00Z)" '. + {"3": {jobs: [$c]}}' <<<"$STUB_JOBS")"
STUB_NOTES="$(jq -c --argjson c "[$(hold_note trust-gate)]" '. + {"31": $c}' <<<"$STUB_NOTES")"
export STUB_RUNS STUB_JOBS STUB_NOTES
nodecided
decided "$HEAD" 2026-10-23T13:05:00Z
expect "an earlier trust-gate hold nobody trusted lifted keeps the label" no no no "is not cost-only"
STUB_EVENTS="[$(event labeled "$LANE" 2026-10-23T13:09:58Z),$(event unlabeled "$STRANGER" 2026-10-23T13:15:00Z),$(event labeled "$LANE" 2026-10-23T13:20:20Z)]"
expect "an untrusted removal of a trust-gate hold does not open the window" no no no "is not cost-only"
STUB_EVENTS="[$(event labeled "$LANE" 2026-10-23T13:09:58Z),$(jq -c '.performed_via_github_app = {slug: "x"}' <<<"$(event unlabeled "$OWNER" 2026-10-23T13:15:00Z)"),$(event labeled "$LANE" 2026-10-23T13:20:20Z)]"
expect "a removal an App made for a trusted person does not open the window" no no no "is not cost-only"
STUB_EVENTS="[$(event labeled "$LANE" 2026-10-23T13:09:58Z),$(event unlabeled "$OWNER" 2026-10-23T13:15:00Z),$(event labeled "$LANE" 2026-10-23T13:20:20Z)]"
expect "a trusted person's removal of the trust-gate hold opens a new window" yes yes yes

reset
STUB_COMMENTS="[$(comment "$APP" 2026-10-23T05:39:35Z '<!-- work-items:escalation lane=pr-unblock kind=escalated -->')]"
expect "a lanes App escalation with no trusted removal since keeps the label" no no no "lanes App escalated"
lifted
expect "a lanes App escalation before the window does not keep the label" yes yes yes
STUB_COMMENTS="[$(comment "$APP" 2026-10-23T13:22:00Z '<!-- work-items:escalation lane=pr-unblock kind=escalated -->')]"
expect "a lanes App escalation in the window keeps the label" no no no "lanes App escalated"
STUB_COMMENTS="[$(jq -c '.updated_at = "2026-10-23T13:22:00Z"' <<<"$(comment "$APP" 2026-10-23T05:39:35Z '<!-- work-items:escalation lane=pr-unblock kind=escalated -->')")]"
expect "a lanes App escalation edited in the window keeps the label" no no no "lanes App escalated"
STUB_COMMENTS="[$(comment "$APP" 2026-10-23T13:22:00Z 'Replied to the review thread.')]"
expect "a lanes App comment in the window that is no escalation does not keep the label" yes yes yes
reset
lifted
export STUB_DELETED='{"data":{"repository":{"pullRequest":{"timelineItems":{"filteredCount":1,"nodes":[{"createdAt":"2026-10-23T13:21:30Z"}]}}}}}'
expect "a comment deleted in the window keeps the label" no no no "was deleted"
export STUB_DELETED='{"data":{"repository":{"pullRequest":{"timelineItems":{"filteredCount":1,"nodes":[{"createdAt":"2026-10-23T10:00:00Z"}]}}}}}'
expect "a comment deleted before the window does not keep the label" yes yes yes
export STUB_DELETED='{"data":{"repository":{"pullRequest":{"timelineItems":{"filteredCount":101,"nodes":[]}}}}}'
expect "more deletions than one page shows keeps the label" no no no "was deleted"
# Deleting a hold comment moves no decided head: the notices decide it.
reset
lifted
STUB_COMMENTS="[$(marker "$OLD" 2026-10-23T13:12:00Z)]"
export STUB_COMMENTS
export STUB_DELETED='{"data":{"repository":{"pullRequest":{"timelineItems":{"filteredCount":1,"nodes":[{"createdAt":"2026-10-23T13:11:00Z"}]}}}}}'
expect "a comment deleted before the window, after the decided notice, does not stop the carry" yes yes yes
# A late event for an older head lifts nothing off the live one.
reset
STUB_PR="$(jq -c --arg o "$OLD" '.head.sha = $o' <<<"$STUB_PR")"
expect "a pull request whose head moved since the event clears nothing" no no no "the head moved since this event"

reset
STUB_EVENTS="[$(event labeled "$OWNER" 2026-10-23T13:20:20Z)]"
expect "a label a person added clears nothing" no no no "someone other than a review lane"
STUB_EVENTS="[$(event labeled "$APP" 2026-10-23T13:20:20Z)]"
expect "a label the lanes App added clears nothing" no no no "someone other than a review lane"
STUB_EVENTS="[$(event labeled "$LANE" 2026-10-23T12:59:00Z)]"
expect "a lane label with no held review within ten minutes clears nothing" no no no "no held review after it"
STUB_EVENTS='[]'
expect "a hold with no label event clears nothing" no no no "no label was added"
if [[ "$(grep -c '^api ' "$TMP_ROOT/log")" -eq 1 ]] && grep -q '^api repos/o/r/issues/6419/events' "$TMP_ROOT/log"; then
  ok "with no lane label event the events are the step's one read"
else
  fail "with no lane label event the step read more than the events: '$(cat "$TMP_ROOT/log")'"
fi
export STUB_TRACKER='{"config":{"role_labels":{"human-gated":"owner-call"}}}'
STUB_EVENTS="[$(jq -c '.label.name = "owner-call"' <<<"$(event labeled "$OWNER" 2026-10-23T13:20:20Z)")]"
expect "the base tracker's human-gated label is the one judged" no no no "someone other than a review lane"
export STUB_TRACKER='{not json'
expect "an invalid tracker config clears nothing" no no no "the tracker config is invalid"
# A pull_request run takes its workflow from the head, so a head that edits a
# lane workflow could write the cost notice itself.
reset
STUB_COMPARE="$(jq -cn --arg h "$HEAD" '{($h): {files: [{filename: ".github/workflows/pr-review-security-hosted.yml"}]}}')"
expect "a lane run on a head that changes a review-lane workflow clears nothing" no no no "changes a review-lane workflow"
STUB_COMPARE="$(jq -cn --arg h "$HEAD" '{($h): {files: [range(300) | {filename: "f\(.)"}]}}')"
expect "a lane run on a head whose comparison hits the file cap clears nothing" no no no "changes too many files"
STUB_COMPARE="$(jq -cn --arg h "$HEAD" '{($h): {status: "diverged"}}')"
expect "a comparison with no file list clears nothing" no no no "do not parse"
reset
lanes '[]' '[]'
lifted
expect "a label with no recorded hold clears nothing" no no no "no review lane recorded a hold"
reset
export LANES_APP_ID=''
expect "an unset lanes App id clears nothing" no no no

for read in tracker actors events pull runs compare jobs notes comments deleted closing decision edited; do
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
