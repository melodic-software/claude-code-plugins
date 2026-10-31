#!/usr/bin/env bash
# Runs the `Require both review lanes on this head` step body of
# .github/workflows/pr-require-checks.yml's ci-status under the shell Actions
# gives a step with no `shell:` (bash -e), against stub `gh` and `sleep`.
#
# On a ready pull request, ci-status passes only when the newest pull_request
# run of each review caller on the head has a successful status job whose
# `Apply the hold` step ran, or whose no-change skip record leads back to such
# a review on the pull request. Pending, failed, skipped or missing reviews fail
# with the cause named, a lane the kill switch stopped among them; Dependabot, the
# release App and the standards-sync App are exempt by numeric author id, but
# not from a trust-gate path (with merge.diff-check.path-holds false, only
# Dependabot is held for one, unless it only bumps actions of owners in the
# base's merge.dependabot.trusted-action-owners) unless a person on the base's
# trusted-actor list approves the head, and neither is a pull request an agent App
# (merge.trust-path-hold-apps at the base) opened, wrote a commit of or pushed
# to. It fails closed when it cannot read.
# test-scope: .github/workflows/pr-require-checks.yml docs/conventions/pr-pipeline.yaml
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

NAME='Require both review lanes on this head'
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
if [[ "$step" == *"if: \${{ !cancelled() && github.event_name == 'pull_request' && github.event.pull_request.draft == false }}"* ]]; then
  ok "step runs on every ready pull_request run, contract-only ones included"
else
  fail "step lost its ready pull_request condition"
fi
# The skip-chain lookup (`lane_at`, `carried`) filters runs to this pull
# request by PR_NUMBER, so the step's env must set it from the event.
if [[ "$step" == *$'\n          PR_NUMBER: ${{ github.event.pull_request.number }}\n'* ]]; then
  ok "step env sets PR_NUMBER from the pull_request event"
else
  fail "step env does not set PR_NUMBER from github.event.pull_request.number"
fi
if [[ "$step" == *"continue-on-error"* ]]; then
  fail "step must not continue on error: its exit code is the gate"
else
  ok "step fails the job on its exit code"
fi
order="$(grep -nE "^  ci-status:$|^      - name: ($NAME|Aggregate lane results)$" "$WORKFLOW" | cut -d: -f1 | paste -sd' ')"
read -r job_line agg_line lanes_line <<<"$order"
if [[ -n "${lanes_line:-}" && "$job_line" -lt "$agg_line" && "$agg_line" -lt "$lanes_line" ]]; then
  ok "step sits in ci-status after the aggregate, so a contract-only run's hold is not cut short by a review still running"
else
  fail "step is not inside ci-status after the aggregate (lines: $order)"
fi

# The exempt ids are the trusted-actor list's Dependabot, release App and
# standards-sync App.
ACTORS="$ROOT/.github/standards/trusted-actors/trusted-actors.json"
want_ids="$(jq -r '[.actors[] | select(.login == "dependabot[bot]" or .login == "melodic-plugin-release[bot]" or .login == "melodic-standards-sync[bot]") | .id] | sort | join(" ")' "$ACTORS")"
got_ids="$(sed -nE "s/^exempt_author_ids='([0-9 ]+)'$/\1/p" "$TMP_ROOT/body.sh" | tr ' ' '\n' | sort -n | paste -sd' ')"
if [[ -n "$got_ids" && "$got_ids" == "$want_ids" ]]; then
  ok "the exempt author ids are Dependabot's, the release App's and the standards-sync App's ($got_ids)"
else
  fail "exempt author ids '$got_ids' are not the trusted-actor list's Dependabot, release App and standards-sync App '$want_ids'"
fi

# Each review caller publishes comments with a hold label, the only runs whose
# `Apply the hold` step runs, and keeps the job id the check name starts with.
for pair in 'pr-review-hosted.yml pr-review:' 'pr-review-security-hosted.yml pr-review-security:'; do
  read -r file job <<<"$pair"
  caller="$ROOT/.github/workflows/$file"
  if grep -qxF "  $job" "$caller" && grep -qxF '      publish: comments' "$caller" &&
    grep -qxF '      hold-label: needs-human' "$caller" &&
    grep -qE '^    uses: melodic-software/ci-workflows/\.github/workflows/pr-review-cli\.yml@main$' "$caller"; then
    ok "$file calls pr-review-cli as job ${job%:} with publish: comments and hold-label: needs-human"
  else
    fail "$file lost its job id, publish: comments, hold-label or @main ref"
  fi
  # pr-review-cli's check-key-credit job requests actions: read; a caller that
  # does not grant it fails at startup.
  if awk -v job="  $job" '$0 == job { on = 1; next } on && /^  [^ ]/ { exit } on && /^      actions: read( |$)/ { found = 1 } END { exit !found }' "$caller"; then
    ok "$file grants actions: read to job ${job%:}"
  else
    fail "$file does not grant actions: read to job ${job%:}"
  fi
  paths="$(awk '/^      hold-paths: \|$/ { on = 1; next } on && /^        / { sub(/^ +/, ""); print; next } on { exit }' "$caller")"
  # test_merge_holds_sync.py checks the list covers the path floor; here the
  # two callers agree and keep the trusted-actor list and the security
  # review's own files.
  first_paths="${first_paths-$paths}"
  if [[ "$paths" == "$first_paths" && $'\n'"$paths"$'\n' == *$'\n.github/standards/trusted-actors/**\n'* &&
    $'\n'"$paths"$'\n' == *$'\nplugins/review/skills/security-review/**\nplugins/review/evals/security-review-*/**\n' ]]; then
    ok "$file names the same hold-paths as pr-review-hosted.yml, ending with the security review's own files"
  else
    fail "$file hold-paths are '$paths'"
  fi
done

# Both callers run pr-review-cli at the same ref.
pins="$(sed -nE 's/^    uses: .*pr-review-cli\.yml@([^ ]+).*/\1/p' "$ROOT/.github/workflows/pr-review-hosted.yml" "$ROOT/.github/workflows/pr-review-security-hosted.yml" | sort -u)"
if [[ -n "$pins" && "$pins" != *$'\n'* ]]; then
  ok "both review callers run pr-review-cli at one ref"
else
  fail "the review callers run pr-review-cli at different or no refs: ${pins//$'\n'/ }"
fi

# The trust-gate paths in bash form, as sync-hold-floor.py writes them:
# `**/X` is X or */X, a trailing `**` is `*`. The security review's own files
# in hold-paths are scrutiny only.
want_patterns="$(grep -v '^plugins/review/' <<<"$first_paths" | sed -E 's#/\*\*$#/*#; s#^\*\*/(.*)$#\1\n*/\1#' | sort)"
got_patterns="$(sed -nE 's/^ *hold_patterns=\((.*)\)$/\1/p' "$TMP_ROOT/body.sh" | tr ' ' '\n' | tr -d "'" | sort)"
if [[ -n "$want_patterns" && "$got_patterns" == "$want_patterns" ]]; then
  ok "the exempt-author hold patterns are the trust-gate paths"
else
  fail "exempt-author hold patterns '$got_patterns' are not the trust-gate paths '$want_patterns'"
fi
# Owner decisions Q21 and Q24 (2026-10-29): with merge.diff-check.path-holds
# false a generated guard empties the list for every author but Dependabot,
# whose action-pin bumps bring in third-party code; true holds them all.
dependabot_id="$(jq -r '.actors[] | select(.login == "dependabot[bot]") | .id' "$ACTORS")"
guard="[ \"\$AUTHOR_ID\" = $dependabot_id ] || hold_patterns=()"
guards="$(grep -cxF "  $guard" "$TMP_ROOT/body.sh")"
if [[ "$(yq '.merge."diff-check"."path-holds" // false' "$ROOT/docs/conventions/pr-pipeline.yaml")" == false && "$guards" == 1 ]]; then
  ok "with path-holds false only Dependabot ($dependabot_id) keeps the exempt-author hold"
else
  fail "the Dependabot guard '$guard' appears $guards times; it does not follow merge.diff-check.path-holds false"
fi
# body.live.sh is the step as committed (path-holds false). body.sh, used
# below, has the block as the generator writes it with path-holds true, so
# turning path-holds back on is tested before it is needed.
cp "$TMP_ROOT/body.sh" "$TMP_ROOT/body.live.sh"
hardened="hold_patterns=($(awk -v q="'" '{ printf "%s%s%s%s", (NR > 1 ? " " : ""), q, $0, q }' <<<"$want_patterns"))"
awk -v line="$hardened" '/# BEGIN hold-floor hold_patterns/ { print; match($0, /^ */); print substr($0, 1, RLENGTH) line; skip = 1; next }
  /# END hold-floor hold_patterns/ { skip = 0 } !skip { print }' \
  "$TMP_ROOT/body.sh" >"$TMP_ROOT/body.hardened" && mv "$TMP_ROOT/body.hardened" "$TMP_ROOT/body.sh"
if grep -qF 'hold_patterns=()' "$TMP_ROOT/body.sh"; then
  fail "the path-holds true body still empties the list"
else
  ok "the path-holds true body holds every exempt author"
fi

# The base commit's config names the agent App.
mkdir -p "$TMP_ROOT/base-config/docs/conventions" "$TMP_ROOT/bare-config/docs/conventions"
printf 'merge:\n  trust-path-hold-apps:\n    - melodic-agent[bot]\n' >"$TMP_ROOT/base-config/docs/conventions/pr-pipeline.yaml"
printf 'merge:\n  rung: C2\n' >"$TMP_ROOT/bare-config/docs/conventions/pr-pipeline.yaml"

# The stub logs its arguments. A runs read fails its first STUB_RUNS_FAILS
# calls, then prints RUNS_CODE or RUNS_SEC by caller file. A jobs read fails
# when STUB_JOBS_FAIL is set, else prints the JOBS_<run id> variable.
mkdir -p "$TMP_ROOT/bin"
cat >"$TMP_ROOT/bin/gh" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$STUB_LOG"
case "$*" in
*/actions/workflows/pr-review-hosted.yml/runs*)
  [[ "$(grep -c '/runs?' "$STUB_LOG")" -gt "${STUB_RUNS_FAILS:-0}" ]] || { echo '{"message":"Server Error"}'; exit 1; }
  printf '%s\n' "$RUNS_CODE"
  ;;
*/actions/workflows/pr-review-security-hosted.yml/runs*)
  printf '%s\n' "$RUNS_SEC"
  ;;
*/actions/runs/*/jobs*)
  [[ -z "${STUB_JOBS_FAIL:-}" ]] || exit 1
  id="$*"
  id="${id#*actions/runs/}"
  id="${id%%/*}"
  var="JOBS_$id"
  printf '%s\n' "${!var:-}"
  ;;
*/pulls/*/files*)
  [[ -z "${STUB_FILES_FAIL:-}" ]] || exit 1
  while [[ $# -gt 0 && "$1" != --jq ]]; do shift; done
  jq -r "$2" <<<"${STUB_FILES:-[]}"
  ;;
*/pulls/*/commits*)
  [[ -z "${STUB_COMMITS_FAIL:-}" ]] || exit 1
  printf '%s\n' "${STUB_COMMITS:-[]}"
  ;;
*/activity*)
  # Page N (after=pN, page 1 without it) prints STUB_PUSHES_N (page 1:
  # STUB_PUSHES); with -i, a Link to page N+1 while STUB_PUSHES_<N+1> is set (empty too)
  # or STUB_PUSHES_ENDLESS is. STUB_LINK=prev gives a Link with rel="prev"
  # only; unread, a next link the step's parse misses; any other value, a
  # next link to that path.
  [[ -z "${STUB_PUSHES_FAIL:-}" ]] || exit 1
  n=1 args="$*"
  [[ "$args" != *after=p* ]] || { n="${args#*after=p}"; n="${n%%[!0-9]*}"; }
  var="STUB_PUSHES_$n"
  [[ $n -ne 1 ]] || var=STUB_PUSHES
  if [[ " $* " == *" -i "* ]]; then
    printf 'HTTP/2.0 200 OK\r\nContent-Type: application/json\r\n'
    next="STUB_PUSHES_$((n + 1))"
    if [[ "${STUB_LINK:-}" == prev ]]; then
      printf 'Link: <https://api.github.com/repositories/1/activity?per_page=100&before=p0>; rel="prev"\r\n'
    elif [[ "${STUB_LINK:-}" == unread ]]; then
      printf 'Link: <https://api.github.com/repositories/1/activity?after=p2>;rel=next\r\n'
    elif [[ -n "${STUB_LINK:-}" ]]; then
      printf 'Link: <https://api.github.com/%s>; rel="next"\r\n' "$STUB_LINK"
    elif [[ -n "${!next+set}${STUB_PUSHES_ENDLESS:-}" ]]; then
      printf 'Link: <https://api.github.com/repositories/1/activity?ref=refs%%2Fheads%%2Ffeature%%2Fx&direction=desc&per_page=100&after=p%s>; rel="next", <https://api.github.com/repositories/1/activity?per_page=100>; rel="first"\r\n' "$((n + 1))"
    fi
    printf '\r\n'
  fi
  printf '%s\n' "${!var-[]}"
  ;;
*/pulls/*/reviews*)
  [[ -z "${STUB_REVIEWS_FAIL:-}" ]] || exit 1
  printf '%s\n' "${STUB_REVIEWS:-[]}"
  ;;
*/pulls/*) jq -cn --argjson n "${STUB_CHANGED:-0}" --argjson c "${STUB_COMMIT_COUNT:-0}" --arg u "${STUB_AUTHOR:-kyle-sexton}" \
  '{changed_files: $n, commits: $c, user: {login: $u}}' ;;
*/check-runs/*/annotations*)
  [[ -z "${STUB_NOTES_FAIL:-}" ]] || exit 1
  id="$*"
  id="${id#*check-runs/}"
  id="${id%%/*}"
  var="NOTES_$id"
  printf '%s\n' "${!var:-[]}"
  ;;
*) exit 1 ;;
esac
EOF
printf '#!/usr/bin/env bash\n' >"$TMP_ROOT/bin/sleep"
chmod +x "$TMP_ROOT/bin/gh" "$TMP_ROOT/bin/sleep"

HEAD=0123456789abcdef0123456789abcdef01234567
CODE=pr-review-hosted.yml
SEC=pr-review-security-hosted.yml
CODE_CHECK='pr-review / claude-review-status'
SEC_CHECK='pr-review-security / security-review'
# run <id> <file> [status] [sha] [event] [head repository] [pull request number]
run() { jq -cn --argjson id "$1" --arg f "$2" --arg st "${3:-completed}" --arg sha "${4:-$HEAD}" --arg ev "${5:-pull_request}" --arg hr "${6:-o/r}" \
  --argjson pr "${7:-77}" '{id: $id, path: (".github/workflows/" + $f), status: $st, head_sha: $sha, event: $ev, head_repository: {full_name: $hr},
    pull_requests: [{number: $pr}], html_url: ("https://github.com/o/r/actions/runs/\($id)")}'; }
runs() { local IFS=,; printf '{"workflow_runs":[%s]}' "$*"; }
# status <name> <status> <conclusion> [hold-step-conclusion]
status() { jq -cn --arg n "$1" --arg st "$2" --arg c "$3" --arg h "${4:-success}" \
  '{id: 9, name: $n, status: $st, conclusion: (if $c == "" then null else $c end),
    steps: [{name: "Publish the review", conclusion: $c}, {name: "Apply the hold", conclusion: $h}, {name: "Upload the shadow report", conclusion: "skipped"}]}'; }
# kill <conclusion> <report-step-conclusion>
kill_job() { jq -cn --arg c "$1" --arg r "$2" '{id: 1, name: "kill-switch", status: "completed", conclusion: $c,
  steps: [{name: "Check the kill switch", conclusion: $c}, {name: "Report the kill switch", conclusion: $r}]}'; }
jobs() { local IFS=,; printf '{"jobs":[%s]}' "$*"; }

expect() {
  local label="$1" want_rc="$2" out rc
  : >"$TMP_ROOT/log"
  # SHARED_FILES stands for the pages the broker step left under RUNNER_TEMP.
  rm -rf "$TMP_ROOT/pr-files.json" "$TMP_ROOT/pr-reads"
  [[ -z "${SHARED_FILES:-}" ]] || printf '%s\n' "$SHARED_FILES" >"$TMP_ROOT/pr-files.json"
  out="$(PATH="${STUB_PATH:+$STUB_PATH:}$TMP_ROOT/bin:$PATH" STUB_LOG="$TMP_ROOT/log" GITHUB_REPOSITORY=o/r GITHUB_REPOSITORY_ID=1 HEAD_SHA="${HEAD_SHA-$HEAD}" BASE_SHA="${BASE_SHA-fedcba9876543210fedcba9876543210fedcba98}" \
    AUTHOR_ID="${AUTHOR_ID-153232337}" HEAD_REPO="${HEAD_REPO-o/r}" PR_NUMBER="${PR_NUMBER-77}" HEAD_REF="${HEAD_REF-feature/x}" \
    BASE_CONFIG="${BASE_CONFIG-$TMP_ROOT/base-config}" RUNNER_TEMP="$TMP_ROOT" bash -e "${BODY-$TMP_ROOT/body.sh}" 2>&1)" && rc=0 || rc=$?
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

PASS_CODE="$(jobs "$(kill_job success skipped)" "$(status "$CODE_CHECK" completed success)")"
PASS_SEC="$(jobs "$(kill_job success skipped)" "$(status "$SEC_CHECK" completed success)")"
export RUNS_CODE RUNS_SEC JOBS_10 JOBS_11 JOBS_20 JOBS_21
RUNS_CODE="$(runs "$(run 10 $CODE)")" RUNS_SEC="$(runs "$(run 20 $SEC)")"
JOBS_10="$PASS_CODE" JOBS_20="$PASS_SEC"
expect "both lanes reviewed the head" 0 "'$CODE_CHECK' passed on $HEAD" "::error::"
if grep -qxF "api repos/o/r/actions/workflows/$CODE/runs?head_sha=$HEAD&event=pull_request&per_page=100" "$TMP_ROOT/log" &&
  grep -qxF "api repos/o/r/actions/runs/10/jobs?filter=latest&per_page=100" "$TMP_ROOT/log"; then
  ok "the head's pull_request runs and the newest run's latest jobs are read"
else
  fail "unexpected reads: '$(sort -u "$TMP_ROOT/log")'"
fi

# The newest run decides, whatever the list order.
RUNS_CODE="$(runs "$(run 11 $CODE)" "$(run 10 $CODE)")"
JOBS_11="$(jobs "$(kill_job success skipped)" "$(status "$CODE_CHECK" in_progress '')")"
expect "a newer run still reviewing is pending" 1 "::error::'$CODE_CHECK' has not finished on $HEAD (https://github.com/o/r/actions/runs/11)."
RUNS_CODE="$(runs "$(run 11 $CODE in_progress)" "$(run 10 $CODE)")" JOBS_11="$(jobs "$(kill_job success skipped)")"
expect "a newer run whose review jobs are not listed yet is pending" 1 "'$CODE_CHECK' has not finished"
RUNS_CODE="$(runs "$(run 10 $CODE)" "$(run 11 $CODE completed "${HEAD//0/f}")" "$(run 12 pr-review-shadow.yml)" "$(run 13 $CODE completed "$HEAD" push)")"
expect "runs on another head, of another file or event do not count" 0 "passed on $HEAD (https://github.com/o/r/actions/runs/10)" "::error::"
# A fork's run on the same commit is newest; only this repository's head counts.
RUNS_CODE="$(runs "$(run 11 $CODE completed "$HEAD" pull_request fork/r)" "$(run 10 $CODE)")"
JOBS_11="$(jobs "$(kill_job success skipped)" "$(status "$CODE_CHECK" completed failure)")"
expect "a newer run from a fork's head with the same commit does not count" 0 "passed on $HEAD (https://github.com/o/r/actions/runs/10)" "::error::"
RUNS_CODE="$(runs "$(run 11 $CODE completed "$HEAD" pull_request fork/r)")"
expect "a fork's run alone leaves the lane missing" 1 "::error::'$CODE_CHECK' is missing: no $CODE run on $HEAD yet."
RUNS_CODE="$(runs "$(run 10 $CODE)")"
# A fork pull request is named as a fork before any run is read, never as missing.
RUNS_CODE="$(runs "$(run 11 $CODE completed "$HEAD" pull_request fork/r)")"
HEAD_REPO=fork/r expect "a fork pull request fails as a fork, not as missing" 1 \
  "::error::'$SEC_CHECK' did not run on $HEAD (head repository: fork/r): a fork, or a bot outside the caller's allowed-bot-sender-ids, gets no review" "is missing"
if grep -q '/actions/' "$TMP_ROOT/log"; then fail "a fork pull request's run read the review runs"; else ok "a fork pull request's run reads no review run"; fi
RUNS_CODE="$(runs "$(run 10 $CODE)")"

RUNS_CODE="$(runs)"
expect "no review run yet fails" 1 "::error::'$CODE_CHECK' is missing: no $CODE run on $HEAD yet."
RUNS_CODE="$(runs "$(run 10 $CODE)")"

for c in failure cancelled timed_out; do
  JOBS_10="$(jobs "$(kill_job success skipped)" "$(status "$CODE_CHECK" completed "$c")")"
  expect "a review that ended $c fails" 1 "::error::'$CODE_CHECK' ended $c on $HEAD"
done
JOBS_10="$(jobs "$(kill_job success skipped)" "$(status "$CODE_CHECK" completed success skipped)")"
expect "a green status job whose hold step did not run (summary mode) does not count" 1 \
  "::error::'$CODE_CHECK' passed in https://github.com/o/r/actions/runs/10, but its 'Apply the hold' step did not run"
# A skipped hold step reads the job's annotations, for a no-change skip record.
if grep -qxF "api repos/o/r/check-runs/9/annotations?per_page=100" "$TMP_ROOT/log"; then
  ok "a skipped hold step reads the status job's annotations"
else
  fail "a skipped hold step did not read the annotations: '$(sort -u "$TMP_ROOT/log")'"
fi

# The jobs API can list a finished job's steps empty or cut short; then the
# status job's review-complete notice for this lane and head decides.
# listed <name> <id> <steps json>: a green status job with the given steps.
listed() { jq -cn --arg n "$1" --argjson id "$2" --argjson steps "$3" '{id: $id, name: $n, status: "completed", conclusion: "success", steps: $steps}'; }
# note <level> <title> <message>
note() { jq -cn --arg l "$1" --arg t "$2" --arg m "$3" '{annotation_level: $l, title: $t, message: $m}'; }
notes() { local IFS=,; printf '[%s]'"\n" "$*"; }
COMPLETE="claude-lane-review-complete lane=claude-review sha=$HEAD"
GOOD_NOTES="$(notes "$(note notice api-budget 'token=github-token job=status')" "$(note notice claude-lane-review-complete "$COMPLETE findings=0 inline=0 scope=whole")")"
CUT='[{"number":3,"name":"Fetch the publish gate","status":"completed","conclusion":"success"},{"number":5,"name":"Publish the review","status":"in_progress","conclusion":null},{"number":6,"name":"Apply the hold","status":"pending","conclusion":null}]'
export NOTES_31 NOTES_32
for steps in '[]' "$CUT"; do
  JOBS_10="$(jobs "$(kill_job success skipped)" "$(listed "$CODE_CHECK" 31 "$steps")")" NOTES_31="$GOOD_NOTES"
  expect "a status job listed with steps $(cut -c1-20 <<<"$steps") counts on its review-complete notice" 0 \
    "'$CODE_CHECK' passed on $HEAD (https://github.com/o/r/actions/runs/10): GitHub listed no 'Apply the hold' step with a conclusion" "::error::"
  if grep -qxF "api repos/o/r/check-runs/31/annotations?per_page=100" "$TMP_ROOT/log"; then
    ok "the status job's own check-run annotations are read"
  else
    fail "unexpected reads: '$(sort -u "$TMP_ROOT/log")'"
  fi
done
JOBS_10="$(jobs "$(kill_job success skipped)" "$(listed "$CODE_CHECK" 31 '[]')")"
for case in \
  "no notice|$(notes "$(note notice api-budget 'token=github-token')")" \
  "a notice for another head|$(notes "$(note notice claude-lane-review-complete "claude-lane-review-complete lane=claude-review sha=${HEAD//0/f} findings=0")")" \
  "a notice whose head only starts with this one|$(notes "$(note notice claude-lane-review-complete "${COMPLETE}ab findings=0")")" \
  "a notice for the other lane|$(notes "$(note notice claude-lane-review-complete "claude-lane-review-complete lane=claude-security-review sha=$HEAD findings=0")")" \
  "a hold notice alone|$(notes "$(note notice '' "claude-lane-hold lane=claude-review sha=$HEAD criteria=cost label=needs-human")")" \
  "a summary-mode notice|$(notes "$(note notice '' "shadow claude-review: failure-class=incomplete")")" \
  "a warning that copies the notice|$(notes "$(note warning claude-lane-review-complete "$COMPLETE findings=0")")" \
  "a notice without the record title|$(notes "$(note notice '' "$COMPLETE findings=0")")"; do
  NOTES_31="${case#*|}"
  expect "an unlisted hold step with ${case%%|*} stays uncounted" 1 \
    "::error::'$CODE_CHECK' passed in https://github.com/o/r/actions/runs/10, but GitHub listed no 'Apply the hold' step with a conclusion and the job records no review-complete notice for claude-review on $HEAD"
done
NOTES_31="$GOOD_NOTES" STUB_NOTES_FAIL=1 expect "an unreadable annotation list fails closed" 1 "::error::could not read the annotations of job 31; re-run this run."
# The security lane's notice names its own lane.
JOBS_10="$PASS_CODE" JOBS_20="$(jobs "$(kill_job success skipped)" "$(listed "$SEC_CHECK" 32 '[]')")"
NOTES_32="$(notes "$(note notice claude-lane-review-complete "claude-lane-review-complete lane=claude-security-review sha=$HEAD findings=0 inline=0 scope=whole")")"
expect "the security lane counts on its own lane's notice" 0 "'$SEC_CHECK' passed on $HEAD (https://github.com/o/r/actions/runs/20): GitHub listed no" "::error::"
NOTES_32="$GOOD_NOTES"
expect "the security lane does not count on the code lane's notice" 1 "no review-complete notice for claude-security-review on $HEAD"
JOBS_20="$PASS_SEC"
# A listed hold step keeps the step rule, whatever the notices say.
JOBS_10="$(jobs "$(kill_job success skipped)" "$(listed "$CODE_CHECK" 31 '[{"name":"Publish the review","status":"completed","conclusion":"success"},{"name":"Apply the hold","status":"completed","conclusion":"skipped"}]')")" NOTES_31="$GOOD_NOTES"
expect "a listed skipped hold step stays uncounted despite a review notice" 1 "but its 'Apply the hold' step did not run"
JOBS_10="$(jobs "$(kill_job success skipped)" "$(listed "$CODE_CHECK" 31 '[{"name":"Apply the hold","status":"completed","conclusion":"success"}]')")"
expect "a listed successful hold step passes" 0 "'$CODE_CHECK' passed on $HEAD (https://github.com/o/r/actions/runs/10)." "::error::"
if grep -q '/annotations' "$TMP_ROOT/log"; then fail "a successful hold step read the annotations"; else ok "a successful hold step reads no annotations"; fi

# A push that changed no file of the pull request since a counted review (a
# clean base merge) is a no-change skip: its status job succeeds, its hold
# step is skipped, and its review-complete record names the head it carries
# forward. ci-status counts it only when that head, followed through any
# further no-change skips, had a counted review on this pull request.
T1=1111111111111111111111111111111111111111
T2=2222222222222222222222222222222222222222
SKIPPED_HOLD='[{"name":"Publish the review","status":"completed","conclusion":"skipped"},{"name":"Apply the hold","status":"completed","conclusion":"skipped"}]'
# skip_rec <sha> <through> [suffix]: the no-change skip record notices.
skip_rec() { notes "$(note notice claude-lane-review-complete "claude-lane-review-complete lane=claude-review sha=$1 skip=no-change through=$2${3:-}")"; }
export JOBS_12 JOBS_13 NOTES_33 NOTES_34
JOBS_10="$(jobs "$(kill_job success skipped)" "$(listed "$CODE_CHECK" 33 "$SKIPPED_HOLD")")" NOTES_33="$(skip_rec "$HEAD" "$T1")"
RUNS_CODE="$(runs "$(run 10 $CODE)" "$(run 12 $CODE completed "$T1")")" JOBS_12="$PASS_CODE"
expect "a merge-only push after a full review carries that review" 0 "'$CODE_CHECK' skipped $HEAD (https://github.com/o/r/actions/runs/10) as unchanged since $T1, whose review counts" "::error::"
NOTES_33="$(skip_rec "$HEAD" "$T1" " account=fallback")"
expect "a fallback-account skip record carries the review too" 0 "as unchanged since $T1, whose review counts" "::error::"
# Two clean merges: the first merge's own run is a no-change skip too.
PR_NUMBER='' expect "an empty pull request number fails closed before any skip is followed" 1 "::error::the pull request number '' is not a number."
NOTES_33="$(skip_rec "$HEAD" "$T1")"
JOBS_12="$(jobs "$(kill_job success skipped)" "$(listed "$CODE_CHECK" 34 "$SKIPPED_HOLD")")" NOTES_34="$(skip_rec "$T1" "$T2")"
RUNS_CODE="$(runs "$(run 10 $CODE)" "$(run 12 $CODE completed "$T1")" "$(run 13 $CODE completed "$T2")")" JOBS_13="$PASS_CODE"
expect "two merge-only pushes after a full review carry that review" 0 "as unchanged since $T1, whose review counts" "::error::"
# The through head's review must count on its own terms.
JOBS_13="$(jobs "$(kill_job success skipped)" "$(status "$CODE_CHECK" completed success skipped)")"
expect "a skip chain ending in a summary-mode run does not count" 1 \
  "::error::'$CODE_CHECK' skipped $HEAD in https://github.com/o/r/actions/runs/10 as unchanged since $T1, but no counted review of claude-review on #77 covers $T1"
NOTES_34="$(skip_rec "$T1" "$HEAD")"
expect "a skip chain that loops does not count" 1 "no counted review of claude-review on #77 covers $T1"
NOTES_34="$(notes "$(note notice claude-lane-review-complete "claude-lane-review-complete lane=claude-review sha=$T1 skip=docs-only")")"
expect "a skip chain ending in another kind of skip does not count" 1 "no counted review of claude-review on #77 covers $T1"
JOBS_12="$PASS_CODE"
RUNS_CODE="$(runs "$(run 10 $CODE)")"
expect "a skip through a head with no review run does not count" 1 "no counted review of claude-review on #77 covers $T1"
RUNS_CODE="$(runs "$(run 10 $CODE)" "$(run 12 $CODE completed "$T1" pull_request o/r 78)")"
expect "a skip through a head reviewed only for another pull request does not count" 1 "no counted review of claude-review on #77 covers $T1"
RUNS_CODE="$(runs "$(run 10 $CODE)" "$(run 12 $CODE completed "$T1" pull_request fork/r)")"
expect "a skip through a head reviewed only from a fork does not count" 1 "no counted review of claude-review on #77 covers $T1"
RUNS_CODE="$(runs "$(run 10 $CODE)" "$(run 12 $CODE completed "$T1")")"
NOTES_33="$(skip_rec "$HEAD" "${T1:0:39}")"
expect "a skip record with a malformed through head stays uncounted" 1 "but its 'Apply the hold' step did not run"
# The empty-step-list path reads the same record and follows it the same way.
JOBS_10="$(jobs "$(kill_job success skipped)" "$(listed "$CODE_CHECK" 33 '[]')")" NOTES_33="$(skip_rec "$HEAD" "$T1")"
expect "an unlisted hold step with a skip record carries a counted review" 0 "as unchanged since $T1, whose review counts" "::error::"
JOBS_12="$(jobs "$(kill_job success skipped)" "$(status "$CODE_CHECK" completed success skipped)")"
expect "an unlisted hold step with a skip record through an uncounted head fails" 1 "no counted review of claude-review on #77 covers $T1"
NOTES_33="$(notes "$(note notice claude-lane-review-complete "claude-lane-review-complete lane=claude-review sha=$HEAD skip=docs-only")")"
expect "an unlisted hold step with any other skip record stays uncounted" 1 "the job records no review-complete notice for claude-review on $HEAD"
JOBS_10="$PASS_CODE" RUNS_CODE="$(runs "$(run 10 $CODE)")"


# A kill-switch job listed without its report step counts as a stop only on
# the notice that step writes, as both callers write it.
for caller in pr-review-hosted.yml pr-review-security-hosted.yml; do
  if grep -qE '^ +echo "::notice::a kill switch stops this (security )?review \(' "$ROOT/.github/workflows/$caller"; then
    ok "$caller's kill-switch report writes the notice ci-status reads"
  else
    fail "$caller's kill-switch report no longer writes 'a kill switch stops this [security ]review ('"
  fi
done
export NOTES_41
KILL_UNLISTED='{"id":41,"name":"kill-switch","status":"completed","conclusion":"success","steps":[]}'
JOBS_10="$(jobs "$KILL_UNLISTED")"
NOTES_41="$(notes "$(note notice '' 'a kill switch stops this review (lanes: disabled, CLAUDE_REVIEW_DISABLED: unset)')")"
expect "a kill-switch job listed with no steps counts as a stop on its report notice, and a stop fails" 1 "::error::'$CODE_CHECK' did not run on $HEAD (https://github.com/o/r/actions/runs/10): a kill switch was on when it started." "::notice::"
NOTES_41="$(notes "$(note notice '' 'a kill switch stops this security review (lanes: disabled)')")"
expect "the security lane's kill-switch notice counts too" 1 "::error::'$CODE_CHECK' did not run on $HEAD (https://github.com/o/r/actions/runs/10): a kill switch was on when it started." "::notice::"
NOTES_41="$(notes "$(note notice api-budget 'token=github-token')")"
expect "a kill-switch job listed with no steps and no report notice fails" 1 "did not run on $HEAD (https://github.com/o/r/actions/runs/10; kill-switch job: success)"
NOTES_41="$(notes "$(note warning '' 'a kill switch stops this review (lanes: disabled)')")"
expect "a warning copying the kill-switch notice is no stop" 1 "kill-switch job: success"
RUNS_CODE="$(runs "$(run 10 $CODE in_progress)")"
expect "a running run whose kill-switch steps are unlisted is pending" 1 "'$CODE_CHECK' has not finished"
if grep -q '/annotations' "$TMP_ROOT/log"; then fail "a running run read the annotations"; else ok "a running run reads no annotations"; fi
RUNS_CODE="$(runs "$(run 10 $CODE)")"

JOBS_10="$(jobs "$(kill_job success skipped)" "$(status "$CODE_CHECK" completed skipped skipped)")"
expect "a skipped review (fork or unlisted bot) fails" 1 "::error::'$CODE_CHECK' did not run on $HEAD (https://github.com/o/r/actions/runs/10; kill-switch job: success)"
JOBS_10="$(jobs "$(kill_job success success)")"
expect "a lane the kill switch stopped fails: the kill switch never waives review" 1 \
  "::error::'$CODE_CHECK' did not run on $HEAD (https://github.com/o/r/actions/runs/10): a kill switch was on when it started. Once it is off, the lost-run reconciler re-runs it, or a person on the trusted-actor list re-runs all jobs of https://github.com/o/r/actions/runs/10; ci-status re-runs when it finishes." "::notice::"
JOBS_10="$(jobs "$(kill_job success success)" "$(status "$CODE_CHECK" completed skipped skipped)")"
expect "a kill-switch stop with the review listed as skipped fails" 1 "a kill switch was on when it started" "::notice::"
JOBS_10="$(jobs "$(kill_job success success)")" JOBS_20="$(jobs "$(kill_job success success)")"
expect "both lanes stopped by the kill switch fail, each named" 1 "'$SEC_CHECK' did not run on $HEAD (https://github.com/o/r/actions/runs/20): a kill switch was on when it started"
JOBS_20="$PASS_SEC"
JOBS_10="$(jobs "$(kill_job failure skipped)")"
expect "a failed kill-switch job fails" 1 "kill-switch job: failure"
JOBS_10="$(jobs "$(kill_job success skipped)")"
expect "a kill-switch job that let the review run, with no review, fails" 1 "did not run on $HEAD"

# An upstream-status skip is named, not read as a fork or an unlisted bot:
# the hosted callers' `Stop on upstream status` step fails the kill-switch job
# with its error, and an older run's gate left its notice on a kill-switch job
# that succeeded with the review skipped (runs 41102428120, 41106612430).
for caller in pr-review-hosted.yml pr-review-security-hosted.yml; do
  if grep -qE '^ +echo "::error::an upstream outage stops this (security )?review \(' "$ROOT/.github/workflows/$caller"; then
    ok "$caller's upstream stop writes the error ci-status reads"
  else
    fail "$caller's upstream stop no longer writes 'an upstream outage stops this [security ]review ('"
  fi
done
upstream_job() { jq -cn --argjson id "$1" --arg c "$2" --arg u "$3" --arg r "$4" --arg s "$5" '{id: $id, name: "kill-switch", status: "completed", conclusion: $c,
  steps: [{name: "Check the kill switch", conclusion: "success"}, {name: "Check upstream status", conclusion: $u},
    {name: "Report the kill switch", conclusion: $r}, {name: "Stop on upstream status", conclusion: $s}]}'; }
export NOTES_42 NOTES_43
JOBS_10="$(jobs "$(upstream_job 42 failure success skipped failure)" "$(status "$CODE_CHECK" completed skipped skipped)")"
NOTES_42="$(notes "$(note failure '' 'an upstream outage stops this review (Actions major_outage); the lost-run reconciler re-runs it once GitHub Actions is operational')")"
expect "a review the upstream gate stopped is named, with the reconciler's re-run" 1 \
  "::error::'$CODE_CHECK' did not run on $HEAD (https://github.com/o/r/actions/runs/10): GitHub Actions or npm listed an outage on its status page when it started. Within 24 hours of the run, the lost-run reconciler re-runs its failed jobs once, as soon as neither lists an outage and GitHub Actions is operational. Once that review passes, its dispatch re-runs this ci-status job under the reconciler's record, so pr-verify accepts it; if that re-run does not come, a person re-runs this ci-status job, not the review run; after 24 hours, push to the head." "a fork, or a bot"
JOBS_10="$(jobs '{"id":42,"name":"kill-switch","status":"completed","conclusion":"failure","steps":[]}')"
expect "a failed kill-switch job listed with no steps counts as an upstream stop on its error" 1 "GitHub Actions or npm listed an outage on its status page when it started. Within 24 hours of the run, the lost-run reconciler" "a fork, or a bot"
NOTES_42="$(notes "$(note notice '' 'an upstream outage stops this review (Actions major_outage)')")"
expect "a notice copying the upstream error is no upstream stop" 1 "kill-switch job: failure"
JOBS_10="$(jobs "$(upstream_job 42 failure success skipped skipped)")"
expect "a kill-switch job that failed at another step is no upstream stop" 1 "kill-switch job: failure" "listed an outage"
JOBS_10="$(jobs "$(upstream_job 43 success success skipped skipped)" "$(status "$CODE_CHECK" completed skipped skipped)")"
NOTES_43="$(notes "$(note notice '' 'upstream status: www.githubstatus.com lists Actions as degraded_performance; this run is skipped')")"
expect "an older run's upstream skip notice is named, with a re-run to start" 1 \
  "::error::'$CODE_CHECK' did not run on $HEAD (https://github.com/o/r/actions/runs/10): the upstream status gate skipped it when it started. Once GitHub Actions and npm are operational, re-run all jobs of https://github.com/o/r/actions/runs/10; ci-status re-runs when it finishes." "a fork, or a bot"
NOTES_43="$(notes "$(note notice '' 'upstream status: status.npmjs.org could not be read (offline); the gate fails open for it')")"
expect "a fail-open upstream notice is no skip" 1 "kill-switch job: success" "upstream status gate skipped"
NOTES_43="$(notes "$(note warning '' 'upstream status: www.githubstatus.com lists Actions as major_outage; this run is skipped')")"
expect "a warning copying the skip notice is no skip" 1 "kill-switch job: success" "upstream status gate skipped"

JOBS_10="$PASS_CODE"
RUNS_SEC="$(runs)"
expect "the security lane is required too" 1 "::error::'$SEC_CHECK' is missing" "'$CODE_CHECK' is missing"
RUNS_CODE="$(runs)"
expect "both missing lanes are named" 1 "'$CODE_CHECK' is missing"
RUNS_CODE="$(runs "$(run 10 $CODE)")" RUNS_SEC="$(runs "$(run 20 $SEC)")"

export STUB_FILES STUB_CHANGED PR_NUMBER=77
files() { jq -cn '[$ARGS.positional[] | split("<") | {filename: .[0]} + (if length > 1 then {previous_filename: .[1]} else {} end)]' --args "$@"; }
STUB_FILES="$(files plugins/x/README.md .github/workflows/ci.yml)" STUB_CHANGED=2
for id in 49699333 337859524 300666570; do
  RUNS_CODE="$(runs)"
  AUTHOR_ID=$id expect "author $id is exempt when no trust-gate path changed" 0 "is one no review lane reviews, and no trust-gate path changed"
  if grep -q '/actions/' "$TMP_ROOT/log"; then fail "an exempt author's run read the review runs"; else ok "an exempt author's run reads no review run"; fi
done
if grep -qxF 'api repos/o/r/pulls/77/files?per_page=100 --paginate --jq .[] | [.filename, (.previous_filename // "")] | @tsv' "$TMP_ROOT/log"; then
  ok "an exempt author's PR files are read whole"
else
  fail "unexpected file read: '$(sort -u "$TMP_ROOT/log")'"
fi
# Every hold path the callers list holds an exempt author's PR, nested and renamed ones too,
# in any letter case, as the floor folds case.
for changed in .github/standards/trusted-actors/trusted-actors.json .github/actions/check-trusted-trigger/lib/x.mjs CODEOWNERS .github/CODEOWNERS \
  .github/actions/resolve-config/package-lock.json .github/actions/request-lane-token/action.yml .github/actions/check-kill-switch/check-kill-switch.mjs \
  .github/scripts/pr-merge/merge-holds.mjs plugins/source-control/skills/babysit-prs/scripts/babysit_risk.py \
  .gitmodules vendor/sub/.gitmodules 'docs/new.md<.github/CODEOWNERS' \
  .GitHub/Actions/Request-Lane-Token/action.yml vendor/sub/.GitModules docs/CodeOwners Scripts/Sync-Hold-Floor.PY; do
  STUB_FILES="$(files README.md "$changed")"
  AUTHOR_ID=300666570 expect "an exempt author changing $changed fails" 1 "::error::#77 is by an author no review lane reviews and changes trust-gate paths:"
done
# With path-holds true, each exempt author changing a trust-gate path is held.
for id in 49699333 337859524 300666570; do
  for changed in CODEOWNERS .github/actions/request-lane-token/action.yml .gitmodules; do
    STUB_FILES="$(files "$changed")" STUB_CHANGED=1
    AUTHOR_ID=$id expect "with path-holds on author $id changing $changed fails" 1 "::error::#77 is by an author no review lane reviews and changes trust-gate paths: $changed."
  done
done
# The step as committed, path-holds false: Dependabot is still held (owner
# decision Q24), the release and standards-sync Apps pass (Q21).
for changed in CODEOWNERS .github/actions/request-lane-token/action.yml .gitmodules; do
  STUB_FILES="$(files "$changed")" STUB_CHANGED=1
  BODY="$TMP_ROOT/body.live.sh" AUTHOR_ID=49699333 expect "with path-holds off Dependabot changing $changed fails" 1 "::error::#77 is by an author no review lane reviews and changes trust-gate paths: $changed."
  for id in 337859524 300666570; do
    BODY="$TMP_ROOT/body.live.sh" AUTHOR_ID=$id expect "with path-holds off author $id changing $changed passes" 0 "no trust-gate path changed"
  done
done
for changed in .github/standards/other.json CODEOWNERS.md docs/gitmodules.md .github/actions/check-trusted-trigger-x/a.mjs .github/actions/check-wip-cap/action.yml .github/scripts/pr-merge/gate.mjs \
  plugins/review/skills/security-review/SKILL.md plugins/review/evals/security-review-kill-switch-narrowed/prompt.md; do
  STUB_FILES="$(files "$changed")" STUB_CHANGED=1
  AUTHOR_ID=300666570 expect "an exempt author changing $changed passes" 0 "no trust-gate path changed"
done
STUB_FILES="$(files README.md)" STUB_CHANGED=3
AUTHOR_ID=49699333 expect "a short file listing fails closed" 1 "::error::GitHub listed fewer files than #77 changes"
STUB_CHANGED=1 STUB_FILES_FAIL=1 AUTHOR_ID=49699333 expect "an unreadable file listing fails closed" 1 "::error::could not read the files of #77"
# The broker step's pages are reused, so the files are not read again.
STUB_FILES_FAIL=1 STUB_CHANGED=3 SHARED_FILES="$(files README.md)$(files docs/a.md 'docs/b.md<docs/c.md')" \
  AUTHOR_ID=49699333 expect "the broker step's file pages, across pages, are reused" 0 "no trust-gate path changed"
if grep -q '/files' "$TMP_ROOT/log"; then fail "the files were read again"; else ok "a reused file list makes no files read"; fi
STUB_FILES_FAIL=1 STUB_CHANGED=2 SHARED_FILES="$(files README.md 'docs/new.md<CODEOWNERS')" \
  AUTHOR_ID=49699333 expect "a renamed trust-gate path in the reused list fails" 1 "trust-gate paths: CODEOWNERS."
STUB_FILES_FAIL=1 STUB_CHANGED=4 SHARED_FILES="$(files README.md)" \
  AUTHOR_ID=49699333 expect "a reused list shorter than the change fails closed" 1 "::error::GitHub listed fewer files than #77 changes"
STUB_FILES='[]' STUB_CHANGED=0
AUTHOR_ID=49699333999 expect "an id that only contains an exempt id is not exempt" 1 "is missing"
# A person on the base commit's trusted-actor list approving the head in their
# newest review clears an exempt author's trust-gate hold.
mkdir -p "$TMP_ROOT/base-config/.github/standards/trusted-actors"
printf '%s\n' '{"actors":[{"kind":"human","id":153232337,"login":"kyle-sexton"},{"kind":"app","id":49699333,"login":"dependabot[bot]"}]}' \
  >"$TMP_ROOT/base-config/.github/standards/trusted-actors/trusted-actors.json"
# review <user id> <state> [commit]
review() { jq -cn --argjson id "$1" --arg st "$2" --arg sha "${3:-$HEAD}" \
  '{user: {id: $id, login: "u\($id)"}, state: $st, commit_id: $sha}'; }
reviews() { local IFS=,; printf '[%s]\n' "$*"; }
CLEAR='a person on the trusted-actor list approving this head clears it.'
export STUB_REVIEWS STUB_REVIEWS_FAIL
STUB_FILES="$(files CODEOWNERS)" STUB_CHANGED=1
STUB_REVIEWS="$(reviews "$(review 153232337 APPROVED)")"
AUTHOR_ID=49699333 expect "a listed person's approval of the head clears an exempt author's hold" 0 \
  "u153232337, a person on the trusted-actor list, approved $HEAD" "::error::"
if grep -qxF 'api repos/o/r/pulls/77/reviews?per_page=100 --paginate' "$TMP_ROOT/log"; then
  ok "the reviews are read live and whole"
else
  fail "unexpected review read: '$(sort -u "$TMP_ROOT/log")'"
fi
STUB_REVIEWS="$(reviews "$(review 153232337 APPROVED)" "$(review 153232337 COMMENTED)")"
AUTHOR_ID=49699333 expect "a comment after the approval keeps it" 0 "approved $HEAD" "::error::"
STUB_REVIEWS="$(reviews "$(review 153232337 APPROVED "${HEAD//0/f}")")"
AUTHOR_ID=49699333 expect "an approval of an older commit does not clear the hold" 1 "A person merges it; $CLEAR"
STUB_REVIEWS="$(reviews "$(review 777 APPROVED)" "$(review 49699333 APPROVED)")"
AUTHOR_ID=49699333 expect "an approval by an account not a listed person does not clear the hold" 1 "A person merges it; $CLEAR"
STUB_REVIEWS="$(reviews "$(review 153232337 APPROVED)" "$(review 153232337 CHANGES_REQUESTED)")"
AUTHOR_ID=49699333 expect "changes requested after the approval keep the hold" 1 "A person merges it; $CLEAR"
STUB_REVIEWS="$(reviews "$(review 153232337 APPROVED)")" STUB_REVIEWS_FAIL=1
AUTHOR_ID=49699333 expect "an unreadable review list keeps the hold" 1 "A person merges it; $CLEAR"
STUB_REVIEWS_FAIL=
STUB_REVIEWS='{"message":"not a list"}'
AUTHOR_ID=49699333 expect "a review answer that is not a list keeps the hold" 1 "A person merges it; $CLEAR"
STUB_REVIEWS="$(reviews "$(review 153232337 APPROVED)")"
BASE_CONFIG="$TMP_ROOT/bare-config" AUTHOR_ID=49699333 expect "an unreadable trusted-actor list keeps the hold" 1 "A person merges it; $CLEAR"
STUB_REVIEWS='[]'
AUTHOR_ID=49699333 expect "with no approval the hold stays" 1 "::error::#77 is by an author no review lane reviews and changes trust-gate paths: CODEOWNERS. A person merges it; $CLEAR"
# Owner decision Q-ANTHROPIC-DEPS: a Dependabot PR whose every change block
# only swaps the ref of an action by an owner the base lists in
# merge.dependabot.trusted-action-owners skips the trust-gate hold; any other
# line, file, status, owner or ref keeps it, and so does an unread patch. Each
# new ref must be a 40-hex SHA a tag of the action's repository points to; the
# git stub answers `ls-remote --tags` with STUB_TAGS, or fails with
# STUB_LSREMOTE_FAIL set; STUB_UNTAGGED_REPO names a repository with no tags.
cat >"$TMP_ROOT/bin/git" <<'EOF'
#!/usr/bin/env bash
printf 'git %s\n' "$*" >>"$STUB_LOG"
[[ " $* " == *" ls-remote --tags https://github.com/"* && -z "${STUB_LSREMOTE_FAIL:-}" ]] || exit 128
[[ -z "${STUB_UNTAGGED_REPO:-}" || " $* " != *" https://github.com/$STUB_UNTAGGED_REPO "* ]] || exit 0
printf '%s\n' "$STUB_TAGS"
EOF
chmod +x "$TMP_ROOT/bin/git"
SHA_OLD=1111111111111111111111111111111111111111 SHA_NEW=2222222222222222222222222222222222222222
SHA_BASE=4444444444444444444444444444444444444444 SHA_UNTAGGED=3333333333333333333333333333333333333333
# The new SHA is the peeled commit of an annotated tag; SHA_BASE a lightweight one.
export STUB_TAGS="aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa	refs/tags/v1.0.266
$SHA_NEW	refs/tags/v1.0.266^{}
$SHA_BASE	refs/tags/v2.0.0
$SHA_UNTAGGED	refs/heads/main"
mkdir -p "$TMP_ROOT/dep-config/docs/conventions"
cp -R "$TMP_ROOT/base-config/.github" "$TMP_ROOT/dep-config/"
printf 'merge:\n  dependabot:\n    trusted-action-owners:\n      - anthropics\n' >"$TMP_ROOT/dep-config/docs/conventions/pr-pipeline.yaml"
WF=.github/workflows/pr-review-hosted.yml
CCA_OLD="anthropics/claude-code-action@$SHA_OLD # v1.0.265"
CCA_NEW="anthropics/claude-code-action@$SHA_NEW # v1.0.266"
# patch_file <file> <changed lines, each starting with + or -> [status]
patch_file() {
  jq -cn --arg f "$1" --arg st "${3:-modified}" --arg body "$2" '($body | split("\n")) as $l
    | [{filename: $f, status: $st, additions: ($l | map(select(startswith("+"))) | length),
      deletions: ($l | map(select(startswith("-"))) | length), patch: ("@@ -10,4 +10,4 @@\n     steps:\n" + $body + "\n       with:")}]'
}
swap() { printf -- '-      - uses: %s\n+      - uses: %s' "$1" "$2"; }
dep() { BODY="$TMP_ROOT/body.live.sh" AUTHOR_ID=49699333 BASE_CONFIG="${BASE_CONFIG-$TMP_ROOT/dep-config}" STUB_FILES_FAIL=1 expect "$@"; }
HELD="changes trust-gate paths: $WF. A person merges it"
STUB_CHANGED=1 SHARED_FILES="$(patch_file "$WF" "$(swap "$CCA_OLD" "$CCA_NEW")")" \
  dep "a Dependabot bump of only a listed owner's action, in Dependabot's form, skips the hold" 0 "owner decision Q-ANTHROPIC-DEPS" "::error::"
if grep -qxF "git -C $TMP_ROOT ls-remote --tags https://github.com/anthropics/claude-code-action" "$TMP_ROOT/log"; then
  ok "the action's own repository's tags are read"
else
  fail "unexpected tag read: '$(grep '^git ' "$TMP_ROOT/log")'"
fi
STUB_CHANGED=1 SHARED_FILES="$(patch_file "$WF" "$(swap "$CCA_OLD" "$CCA_NEW")")" \
  BASE_CONFIG="$ROOT" dep "the repository's own pr-pipeline.yaml lists anthropics (owner decision Q-ANTHROPIC-DEPS)" 0 "owner decision Q-ANTHROPIC-DEPS" "::error::"
STUB_CHANGED=2 SHARED_FILES="$(patch_file "$WF" "$(swap "$CCA_OLD" "$CCA_NEW")")$(patch_file action.yml "$(swap "Anthropics/claude-code-base-action@$SHA_OLD" "Anthropics/claude-code-base-action@$SHA_BASE # v2.0.0")")" \
  dep "a listed owner matches in any letter case, over pages, in an action.yml" 0 "owner decision Q-ANTHROPIC-DEPS" "::error::"
STUB_CHANGED=2 SHARED_FILES="$(patch_file "$WF" "$(swap "$CCA_OLD" "$CCA_NEW")")$(patch_file .github/workflows/ci.yml "$(swap actions/checkout@v4 actions/checkout@v5)")" \
  dep "a mixed bump across files (a listed owner and another) stays held" 1 "$HELD"
STUB_CHANGED=1 SHARED_FILES="$(patch_file "$WF" "-      - uses: $CCA_OLD
-      - uses: actions/checkout@v4
+      - uses: $CCA_NEW
+      - uses: actions/checkout@v5")" \
  dep "a mixed bump in one block stays held" 1 "$HELD"
STUB_CHANGED=1 SHARED_FILES="$(patch_file "$WF" "$(swap "$CCA_OLD" "$CCA_NEW")
-          node-version: 20
+          node-version: 22")" \
  dep "a non-uses line changed beside a listed bump stays held" 1 "$HELD"
STUB_CHANGED=1 SHARED_FILES="$(patch_file "$WF" "+      - uses: $CCA_NEW")" \
  dep "an added step using a listed owner's action stays held" 1 "$HELD"
STUB_CHANGED=1 SHARED_FILES="$(patch_file "$WF" "$(swap "evil/claude-code-action@$SHA_OLD" "$CCA_NEW")")" \
  dep "a swap of another owner's action for a listed one stays held" 1 "$HELD"
STUB_CHANGED=1 SHARED_FILES="$(patch_file "$WF" "$(swap "$CCA_OLD" "anthropics/other-action@$SHA_NEW")")" \
  dep "a swap to a different action of a listed owner stays held" 1 "$HELD"
STUB_CHANGED=1 SHARED_FILES="$(patch_file "$WF" "$(swap "$CCA_OLD" anthropics/claude-code-action@main)")" \
  dep "a swap to a branch name stays held by the ref shape, not the tag read" 1 "$HELD" "No tag of the action's repository"
STUB_CHANGED=1 SHARED_FILES="$(patch_file "$WF" "$(swap "$CCA_OLD" 'anthropics/claude-code-action@v1.0.266 # v1.0.266')")" \
  dep "a swap to a tag name stays held by the ref shape (only SHA pins pass)" 1 "$HELD" "No tag of the action's repository"
STUB_CHANGED=1 SHARED_FILES="$(patch_file "$WF" "$(swap "$CCA_OLD" "anthropics/claude-code-action@$SHA_UNTAGGED # v1.0.266")")" \
  dep "a swap to a SHA no tag points to stays held" 1 "No tag of the action's repository points to, or its tag list could not be read for: anthropics/claude-code-action@$SHA_UNTAGGED"
STUB_LSREMOTE_FAIL=1 STUB_CHANGED=1 SHARED_FILES="$(patch_file "$WF" "$(swap "$CCA_OLD" "$CCA_NEW")")" \
  dep "an unreadable tag list stays held" 1 "$HELD"
STUB_CHANGED=1 SHARED_FILES="$(patch_file "$WF" "$(swap "$CCA_OLD" "anthropics/claude-code-action@$SHA_NEW # v1.0.266; curl -s x | sh")")" \
  dep "a version comment carrying shell text stays held" 1 "$HELD"
STUB_CHANGED=1 SHARED_FILES="$(patch_file "$WF" "$(swap "$CCA_OLD" "$CCA_NEW")
       with:
-          node-version: 20
+          node-version: 22")" \
  dep "a well-ordered non-uses block after a listed bump stays held" 1 "$HELD"
STUB_CHANGED=1 SHARED_FILES="$(patch_file "$WF" "$(swap "$CCA_OLD" "$CCA_NEW")" | jq -c 'map(.previous_filename = ".github/workflows/old.yml")')" \
  dep "a modified file with a previous name stays held" 1 "$HELD"
STUB_CHANGED=1 SHARED_FILES="$(patch_file "$WF" "$(swap "$CCA_OLD" "$CCA_NEW")" | jq -c 'map(.patch = 5)')" \
  dep "a patch that is not a string stays held" 1 "$HELD"
STUB_CHANGED=2 SHARED_FILES="$(patch_file .github/workflows/ci.yml "$(swap "$CCA_OLD" "$CCA_NEW")")$(jq -cn --arg f "$WF" '[{filename: $f, status: "modified", additions: 0, deletions: 0, patch: "@@ -1 +1 @@\n jobs:"}]')" \
  dep "a modified file with no changed line stays held beside a valid bump" 1 "A person merges it"
STUB_UNTAGGED_REPO=anthropics/claude-code-base-action STUB_CHANGED=2 SHARED_FILES="$(patch_file "$WF" "$(swap "$CCA_OLD" "$CCA_NEW")")$(patch_file .github/workflows/ci.yml "$(swap "anthropics/claude-code-base-action@$SHA_OLD" "anthropics/claude-code-base-action@$SHA_NEW # v1.0.266")")" \
  dep "each repository's own tags are read: a second repository without the tag stays held" 1 "for: anthropics/claude-code-base-action@$SHA_NEW" "claude-code-action@$SHA_NEW"
STUB_CHANGED=1 SHARED_FILES="$(patch_file "$WF" "$(swap "anthropics/claude-code-action/sub@$SHA_OLD # v1.0.265" "anthropics/claude-code-action/sub@$SHA_NEW # v1.0.266")")" \
  dep "an action in a subdirectory of a listed repository skips the hold" 0 "owner decision Q-ANTHROPIC-DEPS" "::error::"
if grep -qxF "git -C $TMP_ROOT ls-remote --tags https://github.com/anthropics/claude-code-action" "$TMP_ROOT/log"; then
  ok "a subdirectory action's tags are read from its repository"
else
  fail "subdirectory action read the wrong tags: '$(grep '^git ' "$TMP_ROOT/log")'"
fi
STUB_CHANGED=1 SHARED_FILES="$(patch_file CODEOWNERS "$(swap "$CCA_OLD" "$CCA_NEW")")" \
  dep "a listed bump in a file that is not a workflow or action stays held" 1 "trust-gate paths: CODEOWNERS. A person merges it"
STUB_CHANGED=1 SHARED_FILES="$(patch_file "$WF" "$(swap "$CCA_OLD" "$CCA_NEW")" renamed)" \
  dep "a renamed file stays held" 1 "$HELD"
STUB_CHANGED=1 SHARED_FILES="$(patch_file "$WF" "$(swap "$CCA_OLD" "$CCA_NEW")" | jq -c 'map(del(.patch))')" \
  dep "a file GitHub gave no patch for stays held" 1 "$HELD"
STUB_CHANGED=1 SHARED_FILES="$(patch_file "$WF" "$(swap "$CCA_OLD" "$CCA_NEW")" | jq -c 'map(.additions = 5)')" \
  dep "a patch shorter than its line counts stays held" 1 "$HELD"
STUB_CHANGED=1 STUB_FILES="$(patch_file "$WF" "$(swap "$CCA_OLD" "$CCA_NEW")")" \
  BODY="$TMP_ROOT/body.live.sh" AUTHOR_ID=49699333 BASE_CONFIG="$TMP_ROOT/dep-config" expect "a listed bump with no broker file pages stays held" 1 "$HELD"
STUB_CHANGED=1 SHARED_FILES="$(patch_file "$WF" "$(swap "$CCA_OLD" "$CCA_NEW")")" \
  BASE_CONFIG="$TMP_ROOT/bare-config" dep "a listed bump with the key absent stays held (Q24)" 1 "$HELD"
STUB_CHANGED=1 SHARED_FILES="$(patch_file "$WF" "$(swap "$CCA_OLD" "$CCA_NEW")")" \
  AUTHOR_ID=300666570 BASE_CONFIG="$TMP_ROOT/dep-config" expect "another exempt author's listed bump stays held" 1 "$HELD"
mkdir -p "$TMP_ROOT/dep-bad/docs/conventions"
printf 'merge:\n  dependabot:\n    trusted-action-owners: anthropics\n' >"$TMP_ROOT/dep-bad/docs/conventions/pr-pipeline.yaml"
for bad in "$TMP_ROOT/dep-bad" ''; do
  STUB_CHANGED=1 SHARED_FILES="$(patch_file "$WF" "$(swap "$CCA_OLD" "$CCA_NEW")")" \
    BASE_CONFIG="$bad" dep "an unreadable owner list (${bad:-no base config}) fails closed" 1 "::error::could not read merge.dependabot.trusted-action-owners"
done
mkdir -p "$TMP_ROOT/yq-fails" "$TMP_ROOT/yq-missing"
printf '#!/usr/bin/env bash\necho "[\\"anthropics\\"]"\necho "Error: boom" >&2\nexit 1\n' >"$TMP_ROOT/yq-fails/yq"
printf '#!/usr/bin/env bash\necho "yq: command not found" >&2\nexit 127\n' >"$TMP_ROOT/yq-missing/yq"
chmod +x "$TMP_ROOT/yq-fails/yq" "$TMP_ROOT/yq-missing/yq"
for dir in yq-fails yq-missing; do
  STUB_CHANGED=1 SHARED_FILES="$(patch_file "$WF" "$(swap "$CCA_OLD" "$CCA_NEW")")" \
    STUB_PATH="$TMP_ROOT/$dir" dep "an owner list read with $dir fails closed" 1 "::error::could not read merge.dependabot.trusted-action-owners"
done
STUB_FILES='[]' STUB_CHANGED=0
RUNS_CODE="$(runs "$(run 10 $CODE)")"

# A trust-gate path an agent App touched waits for a person, whoever opened
# the pull request; with no App on it the review lanes decide, as before.
APP='melodic-agent[bot]'
SHA_A=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa SHA_B=bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb
# commit <sha> <author login> <committer login> <email>: "" is an unlinked account.
commit() { jq -cn --arg sha "$1" --arg a "$2" --arg c "$3" --arg e "$4" \
  '{sha: $sha, author: (if $a == "" then null else {login: $a} end), committer: (if $c == "" then null else {login: $c} end),
    commit: {author: {email: $e}, committer: {email: $e}}}'; }
push() { jq -cn --arg a "$1" --arg after "$2" '{activity_type: "push", after: $after, actor: {login: $a, type: "User"}}'; }
list() { local IFS=,; printf '[%s]' "$*"; }
PERSON='153232337+kyle-sexton@users.noreply.github.com'
export STUB_COMMITS STUB_PUSHES STUB_COMMIT_COUNT STUB_AUTHOR
STUB_FILES="$(files README.md .github/actions/resolve-config/resolve.mjs)" STUB_CHANGED=2 STUB_COMMIT_COUNT=1
STUB_COMMITS="$(list "$(commit $SHA_A kyle-sexton kyle-sexton "$PERSON")")"
STUB_PUSHES="$(list "$(push kyle-sexton $SHA_A)")"
expect "a person's trust-gate change with no App on it goes to the review lanes" 0 \
  "No agent App opened, wrote or pushed to #77; the review lanes decide its trust-gate paths." "::error::"
if grep -qxF 'api repos/o/r/pulls/77/commits?per_page=100 --paginate' "$TMP_ROOT/log" &&
  grep -qxF 'api repos/o/r/activity?ref=refs%2Fheads%2Ffeature%2Fx&direction=desc&per_page=100 -i' "$TMP_ROOT/log" &&
  grep -q '/actions/workflows/' "$TMP_ROOT/log"; then
  ok "the commits, the head branch's push history and then the review runs are read"
else
  fail "unexpected reads: '$(sort -u "$TMP_ROOT/log")'"
fi
STUB_PUSHES="$(list "$(push kyle-sexton $SHA_A)" "$(push "$APP" $SHA_B)")"
expect "an App-pushed resolve-config change by a person's commit is held" 1 \
  "::error::#77 changes trust-gate paths: .github/actions/resolve-config/resolve.mjs, and melodic-agent[bot] pushed bbbbbbbbbbbb to it, so no review lane decides it. A person merges it."
if grep -q '/actions/workflows/' "$TMP_ROOT/log"; then fail "a held App change read the review runs"; else ok "a held App change reads no review run"; fi
BASE_CONFIG="$ROOT" expect "the repository's own pr-pipeline.yaml holds no agent App while path holds are off (owner decision Q21)" 0 "No agent App opened, wrote or pushed to #77"
STUB_PUSHES="$(list "$(push kyle-sexton $SHA_A)")"
STUB_AUTHOR="$APP" expect "an App-authored pull request changing a trust-gate path is held" 1 "and melodic-agent[bot] opened it, so no review lane decides it"
# The committed step (path-holds false): the Dependabot guard empties the
# shared list for an App author too, so no App hold applies and the review
# lanes decide.
STUB_AUTHOR="$APP" BODY="$TMP_ROOT/body.live.sh" expect "with path-holds off an App-authored trust-gate change is not held" 0
if grep -q '/commits' "$TMP_ROOT/log"; then fail "with path-holds off the App hold read the commits"; else ok "with path-holds off the App hold reads no commit"; fi
STUB_COMMITS="$(list "$(commit $SHA_A kyle-sexton kyle-sexton "$PERSON")" "$(commit $SHA_B Melodic-Agent[bot] web-flow '')")" STUB_COMMIT_COUNT=2 \
  expect "a commit the App authored, in any letter case, is held" 1 "an agent App authored or committed bbbbbbbbbbbb"
STUB_COMMITS="$(list "$(commit $SHA_B '' '' "1234+$APP@users.noreply.github.com")")" \
  expect "a commit by the App's noreply address with no linked account is held" 1 "an agent App authored or committed bbbbbbbbbbbb"
STUB_COMMITS_FAIL=1 expect "an unreadable commit list is held" 1 "::error::could not read the commits of #77; re-run this run."
STUB_COMMIT_COUNT=2 expect "a commit list shorter than the pull request is held" 1 "::error::GitHub listed fewer commits than #77 has"
STUB_PUSHES_FAIL=1 expect "an unreadable push history is held" 1 "::error::could not read the push history of feature/x; re-run this run."
# The activity API keeps a branch name's history across deletions, so a
# reused name passes a page of 100; every page is read, up to 20.
export STUB_PUSHES_2 STUB_PUSHES_3 STUB_PUSHES_ENDLESS
page() { jq -cn --argjson p "$(push "$1" $SHA_A)" --argjson n "$2" '[range($n) | $p]'; }
STUB_PUSHES="$(page kyle-sexton 100)" STUB_PUSHES_2="$(page kyle-sexton 50)" \
  expect "a push history past one page with no App on it goes to the review lanes" 0 "No agent App opened, wrote or pushed to #77" "::error::"
if grep -qxF 'api repositories/1/activity?ref=refs%2Fheads%2Ffeature%2Fx&direction=desc&per_page=100&after=p2 -i' "$TMP_ROOT/log"; then
  ok "the second page is read from the first page's Link rel=next"
else
  fail "unexpected reads: '$(sort -u "$TMP_ROOT/log")'"
fi
STUB_PUSHES="$(page kyle-sexton 100)" STUB_PUSHES_2="$(jq -c --argjson a "$(push "$APP" $SHA_B)" '.[30] = $a' <<<"$(page kyle-sexton 50)")" \
  expect "an App push on the second page is held" 1 "melodic-agent[bot] pushed bbbbbbbbbbbb to it"
STUB_PUSHES="$(list "$(push "$APP" $SHA_B)")" STUB_PUSHES_2="$(page kyle-sexton 50)" \
  expect "an App push on the first page is held" 1 "melodic-agent[bot] pushed bbbbbbbbbbbb to it"
if grep -q 'after=p2' "$TMP_ROOT/log"; then fail "a held first page read the next page"; else ok "an App push stops the read at its page"; fi
STUB_PUSHES="$(page kyle-sexton 100)" \
  expect "a full page with no Link header is held" 1 "::error::the push history of feature/x fills page 1 with no next link"
STUB_PUSHES="$(page kyle-sexton 100)" STUB_LINK=prev \
  expect "a full page whose Link has only rel=prev is held" 1 "::error::the push history of feature/x fills page 1 with no next link"
STUB_PUSHES="$(page kyle-sexton 99)" \
  expect "a short page with no Link header ends the history" 0 "No agent App opened, wrote or pushed to #77" "::error::"
STUB_PUSHES="$(page kyle-sexton 100)" STUB_PUSHES_2="$(page kyle-sexton 100)" \
  expect "a full last page with no Link header is held" 1 "fills page 2 with no next link"
STUB_PUSHES="$(page kyle-sexton 100)" STUB_PUSHES_ENDLESS=1 \
  expect "a push history past 20 pages is held" 1 "::error::the push history of feature/x runs past 20 pages"
if [[ "$(grep -c '/activity' "$TMP_ROOT/log")" -eq 20 ]]; then ok "the read stops at 20 pages"; else fail "read $(grep -c '/activity' "$TMP_ROOT/log") activity pages"; fi
STUB_PUSHES="$(page kyle-sexton 100)" STUB_PUSHES_2='{"message":"Conflict"}' \
  expect "a non-list body on page 2 is held" 1 "::error::the push history of feature/x is unreadable"
for body in '' 'null'; do
  STUB_PUSHES="$(page kyle-sexton 100)" STUB_PUSHES_2="$body" \
    expect "a second page of '$body' is held" 1 "::error::the push history of feature/x is unreadable"
done
STUB_PUSHES="$(page kyle-sexton 50)" STUB_PUSHES_2="$(list "$(push "$APP" $SHA_B)")" \
  expect "a short first page with a next link reads on to an App push on page 2" 1 "melodic-agent[bot] pushed bbbbbbbbbbbb to it"
STUB_PUSHES="$(page kyle-sexton 50)" STUB_LINK=unread \
  expect "a next link the step cannot parse is held" 1 "::error::the push history of feature/x has a next link this step cannot read"
for link in 'repositories/1/activity?ref=refs%2Fheads%2Ffeature%2Fx&after={owner}' \
  'repositories/2/activity?ref=refs%2Fheads%2Ffeature%2Fx&after=p2' \
  'repositories/1/activity?ref=refs%2Fheads%2Fmain&after=p2' \
  'repos/o/r/activity?ref=refs%2Fheads%2Ffeature%2Fx&after=p2'; do
  STUB_PUSHES="$(page kyle-sexton 50)" STUB_LINK="$link" \
    expect "a next link to $link is held" 1 "::error::the push history of feature/x has a next link outside this repository's activity of the branch"
  if grep -q 'after=' "$TMP_ROOT/log"; then fail "the next link $link was followed"; else ok "the next link $link is not followed"; fi
done
STUB_PUSHES_3="$(page kyle-sexton 1)" STUB_PUSHES="$(page kyle-sexton 100)" STUB_PUSHES_2='{"message":"Conflict"}' \
  expect "a non-array page before a readable one is held" 1 "is unreadable"
# yq failing or missing leaves no list: held, also on a file list at GitHub's
# 3000-file cap that names no trust-gate path, where held is empty.
# yq-fails prints a list and then fails, so only pipefail catches it, whatever
# jq does with empty input.
mkdir -p "$TMP_ROOT/yq-fails" "$TMP_ROOT/yq-missing"
printf '#!/usr/bin/env bash\necho "[]"\necho "Error: boom" >&2\nexit 1\n' >"$TMP_ROOT/yq-fails/yq"
printf '#!/usr/bin/env bash\necho "yq: command not found" >&2\nexit 127\n' >"$TMP_ROOT/yq-missing/yq"
chmod +x "$TMP_ROOT/yq-fails/yq" "$TMP_ROOT/yq-missing/yq"
for dir in yq-fails yq-missing; do
  STUB_PATH="$TMP_ROOT/$dir" expect "a trust-gate change with $dir is held" 1 "::error::could not read merge.trust-path-hold-apps"
  STUB_PATH="$TMP_ROOT/$dir" STUB_CHANGED=3000 SHARED_FILES="$(jq -cn '[range(3000) | {filename: "docs/f\(.).md"}]')" \
    expect "a 3000-file list with $dir is held" 1 "::error::could not read merge.trust-path-hold-apps"
done
BASE_CONFIG='' expect "an unreadable base config is held" 1 "::error::could not read merge.trust-path-hold-apps from pr-pipeline.yaml in the hold config (the default branch's tip at run time, or the base commit for another base)"
printf 'merge:\n  trust-path-hold-apps: melodic-agent[bot]\n' >"$TMP_ROOT/bare-config/docs/conventions/pr-pipeline.yaml"
BASE_CONFIG="$TMP_ROOT/bare-config" expect "a malformed App list is held" 1 "could not read merge.trust-path-hold-apps"
printf 'merge:\n  rung: C2\n' >"$TMP_ROOT/bare-config/docs/conventions/pr-pipeline.yaml"
STUB_AUTHOR="$APP" BASE_CONFIG="$TMP_ROOT/bare-config" expect "a base naming no App holds nothing" 0 "'$CODE_CHECK' passed" "::error::"
if grep -q '/commits\|/activity' "$TMP_ROOT/log"; then fail "a base naming no App read the commits"; else ok "a base naming no App reads no commit or push"; fi
STUB_FILES="$(files README.md docs/a.md)" STUB_AUTHOR="$APP"
expect "an App's pull request changing no trust-gate path still needs both lanes" 0 "'$SEC_CHECK' passed" "::error::"
if grep -qE '/commits|/activity|pulls/77$' "$TMP_ROOT/log"; then fail "a change with no trust-gate path read the pull request, commits or pushes"; else ok "a change with no trust-gate path makes no extra read"; fi
RUNS_CODE="$(runs)"
STUB_AUTHOR="$APP" expect "an App's pull request with no trust-gate path and no review fails as before" 1 "'$CODE_CHECK' is missing"
RUNS_CODE="$(runs "$(run 10 $CODE)")"
STUB_FILES='[]' STUB_CHANGED=0 STUB_AUTHOR=

export STUB_RUNS_FAILS=1
expect "a transient run-list failure is retried" 0 "'$CODE_CHECK' passed"
export STUB_RUNS_FAILS=3
expect "an unreadable run list fails closed" 1 "::error::could not read the $CODE runs on $HEAD; re-run this run."
unset STUB_RUNS_FAILS
export STUB_JOBS_FAIL=1
expect "an unreadable job list fails closed" 1 "::error::could not read the jobs of run 10; re-run this run."
unset STUB_JOBS_FAIL
HEAD_SHA=main expect "a head that is not a commit SHA fails closed" 1 "::error::the head 'main' is not a commit SHA."

test_harness::report
