#!/usr/bin/env bash
# Runs the `Find the ci-status to re-run` and `Re-run ci-status` step bodies
# of .github/workflows/pr-feedback-dispatch.yml's rerun-ci-status job under
# the shell Actions gives a step with no `shell:` (bash -e), against stub `gh`
# and `sleep`.
#
# When a review run completes and the other lane's newest run on the head has
# finished or never ran, the job re-runs only the ci-status job of the newest
# pr-require-checks pull_request run on the reviewed head, after that run
# finishes, polling at most POLL_LIMIT_SECONDS; the find step names the job
# and the rerun-ci-status record of the attempt the re-run starts, which the
# record step uploads before the re-run step re-runs it, unless the review run
# was re-run by anyone but a listed human. The other lane still going, a
# closed PR, a moved head, no run yet, a ci-status not started or one started
# after both lanes finished is left alone. A rate limit waits for its reset
# within the cap, or fails past it. Unreadable reads fail. Each
# path's API call count is pinned, and each response's rate-limit reading is
# kept for the job-end api-budget notice.
# test-scope: .github/workflows/pr-feedback-dispatch.yml
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORKFLOW="$ROOT/.github/workflows/pr-feedback-dispatch.yml"

# shellcheck source=lib/test-harness.sh
. "$ROOT/scripts/lib/test-harness.sh"

TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT

# step_of <name>: the job step of that name, up to the next step or job.
step_of() {
  awk -v name="      - name: $1" '$0 == name { on = 1; print; next }
    on && /^      - / { exit }
    on && /^  [a-z]/ { exit }
    on { print }' "$WORKFLOW"
}
# body_of <step text> <file>: the step's run: | body, dedented.
body_of() {
  awk '/^        run: \|$/ { on = 1; next }
    on && /^          / { print substr($0, 11); next }
    on && /^[[:blank:]]*$/ { print ""; next }
    on { exit }' <<<"$1" >"$2"
}
NAME='Find the ci-status to re-run'
step="$(step_of "$NAME")"
body_of "$step" "$TMP_ROOT/body.sh"
record_step="$(step_of 'Record the re-run')"
rerun_step="$(step_of 'Re-run ci-status')"
body_of "$rerun_step" "$TMP_ROOT/rerun.sh"

if [[ ! -s "$TMP_ROOT/body.sh" || ! -s "$TMP_ROOT/rerun.sh" ]]; then
  fail "no '$NAME' or 'Re-run ci-status' step with a run: | body in $WORKFLOW"
  test_harness::report
  exit 1
fi
# shellcheck disable=SC2016 # the ${{ }} text is workflow source, not shell
for env in 'HEAD_SHA: ${{ github.event.workflow_run.head_sha }}' 'PR_NUMBER: ${{ github.event.workflow_run.pull_requests[0].number }}' \
  'LANE_PATH: ${{ github.event.workflow_run.path }}' 'LANE_DONE_AT: ${{ github.event.workflow_run.updated_at }}' "POLL_LIMIT_SECONDS: '600'" \
  'REVIEW_ATTEMPT: ${{ github.event.workflow_run.run_attempt }}' 'REVIEW_RERUNNER_ID: ${{ github.event.workflow_run.triggering_actor.id }}' \
  'TRUSTED_ACTORS: .base/.github/standards/trusted-actors/trusted-actors.json' \
  'API_BUDGET_SH: .base/.github/actions/log-api-budget/api-budget.bash'; do
  if [[ "$step" == *"$env"* ]]; then ok "step env carries $env"; else fail "step env lacks $env"; fi
done
job="$(awk '/^  rerun-ci-status:$/ { on = 1; next } on && /^  [a-z]/ { exit } on { print }' "$WORKFLOW")"
if [[ "$job" == *$'    permissions:\n      contents: read # '*$'\n      actions: write # '*$'\n      pull-requests: read # '*$'\n    steps:'* ]]; then
  ok "the job holds contents: read, actions: write and pull-requests: read only"
else
  fail "the job's permissions changed"
fi
# The trusted-actors list comes from the default branch, never the PR head,
# and a failed checkout leaves no list rather than failing the re-run.
list_step="$(step_of 'Check out the trusted-actors list')"
# shellcheck disable=SC2016 # the ${{ }} text is workflow source, not shell
for want in 'continue-on-error: true' 'uses: actions/checkout@' 'ref: refs/heads/main' 'path: .base' 'persist-credentials: false' \
  '/.github/standards/trusted-actors/' '/.github/actions/log-api-budget/' 'sparse-checkout-cone-mode: false'; do
  if [[ "$list_step" == *"$want"* ]]; then ok "the list checkout carries '$want'"; else fail "the list checkout lacks '$want'"; fi
done
# The record goes up between the find and the re-run, and each later step
# runs only on the find step's outputs. The job ends by logging its readings.
order="$(grep -nE '^      - name: ' <<<"$job" | cut -d: -f3- | paste -sd'|')"
if [[ "$order" == ' Check out the trusted-actors list| Find the ci-status to re-run| Record the re-run| Re-run ci-status| Log the API budget at the end' ]]; then
  ok "the job finds, records, re-runs, then logs the API budget"
else
  fail "step order: '$order'"
fi
# shellcheck disable=SC2016 # the ${{ }} text is workflow source, not shell
for want in "        id: find" "RECORD_FILE: \${{ runner.temp }}/rerun-ci-status-record.json"; do
  if [[ "$step" == *"$want"* ]]; then ok "the find step carries '$want'"; else fail "the find step lacks '$want'"; fi
done
# shellcheck disable=SC2016 # the ${{ }} text is workflow source, not shell
for want in "if: steps.find.outputs.record != ''" 'uses: actions/upload-artifact@' 'name: ${{ steps.find.outputs.record }}' \
  'path: ${{ runner.temp }}/rerun-ci-status-record.json' 'if-no-files-found: error' 'overwrite: true'; do
  if [[ "$record_step" == *"$want"* ]]; then ok "the record step carries '$want'"; else fail "the record step lacks '$want'"; fi
done
# shellcheck disable=SC2016 # the ${{ }} text is workflow source, not shell
for want in "if: steps.find.outputs.job-id != ''" 'JOB_ID: ${{ steps.find.outputs.job-id }}'; do
  if [[ "$rerun_step" == *"$want"* ]]; then ok "the re-run step carries '$want'"; else fail "the re-run step lacks '$want'"; fi
done
budget_step="$(step_of 'Log the API budget at the end')"
for want in 'if: always()' 'continue-on-error: true' 'uses: ./.base/.github/actions/log-api-budget' 'tokens: github-token'; do
  if [[ "$budget_step" == *"$want"* ]]; then ok "the budget step carries '$want'"; else fail "the budget step lacks '$want'"; fi
done

# The stub logs its arguments. A pulls read prints STUB_PR. A review lane's
# runs read prints STUB_LANE_RUNS and a pr-require-checks runs read STUB_RUNS,
# each failing when its *_FAIL is set. A jobs read prints STUB_JOBS. A read of
# one run prints the next line of STUB_RUN_SEQ (the last line once used up).
# A POST re-run fails when STUB_RERUN_FAIL is set. While STUB_LIMIT_FILE
# holds a count above 0, a pr-require-checks runs read is refused as a
# primary rate limit resetting at STUB_RESET (a 429 with retry-after
# STUB_RETRY_AFTER when that is set), and the count drops by one. The
# sleep stub logs its seconds.
mkdir -p "$TMP_ROOT/bin"
cat >"$TMP_ROOT/bin/gh" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$STUB_LOG"
# A GET read with -i prints a status line and a blank line before the body.
ok200() { printf 'HTTP/2.0 200 OK\r\nX-Ratelimit-Remaining: 9\r\n\r\n%s\n' "$1"; }
if [[ -n "${STUB_LIMIT_FILE:-}" && "$*" == *"/actions/workflows/pr-require-checks.yml/runs"* ]] &&
  [[ "$(cat "$STUB_LIMIT_FILE")" -gt 0 ]]; then
  echo $(($(cat "$STUB_LIMIT_FILE") - 1)) >"$STUB_LIMIT_FILE"
  if [[ -n "${STUB_RETRY_AFTER:-}" ]]; then
    printf 'HTTP/2.0 429 Too Many Requests\r\nRetry-After: %s\r\n\r\n{"message":"You have exceeded a secondary rate limit"}\n' "$STUB_RETRY_AFTER"
  else
    printf 'HTTP/2.0 403 Forbidden\r\nX-Ratelimit-Remaining: 0\r\nX-Ratelimit-Reset: %s\r\n\r\n{"message":"API rate limit exceeded for installation"}\n' "$STUB_RESET"
  fi
  exit 1
fi
# With STUB_ETAG set, a read of one run carries that ETag; a read sent with
# If-None-Match on it is answered 304 (headers only, exit 1, as gh does)
# while STUB_NOT_MODIFIED_FILE holds a count above 0, which drops by one, and
# otherwise with the last line of STUB_RUN_SEQ.
if [[ -n "${STUB_ETAG:-}" && "$*" =~ ^api\ -i\ repos/o/r/actions/runs/[0-9]+($|\ -H) ]]; then
  if [[ "$*" == *" -H If-None-Match: $STUB_ETAG" && "$(cat "$STUB_NOT_MODIFIED_FILE")" -gt 0 ]]; then
    echo $(($(cat "$STUB_NOT_MODIFIED_FILE") - 1)) >"$STUB_NOT_MODIFIED_FILE"
    printf 'HTTP/2.0 304 Not Modified\r\nEtag: %s\r\nX-Ratelimit-Remaining: 9\r\n\r\n' "$STUB_ETAG"
    echo "gh: HTTP 304" >&2
    exit 1
  fi
  if [[ "$*" == *" -H If-None-Match: "* ]]; then body=$(tail -n 1 <<<"$STUB_RUN_SEQ"); else body=$(head -n 1 <<<"$STUB_RUN_SEQ"); fi
  printf 'HTTP/2.0 200 OK\r\nEtag: %s\r\nX-Ratelimit-Remaining: 9\r\n\r\n%s\n' "$STUB_ETAG" "$body"
  exit 0
fi
case "$*" in
*/pulls/*) ok200 "$STUB_PR" ;;
*/actions/workflows/pr-review-hosted.yml/runs* | */actions/workflows/pr-review-security-hosted.yml/runs*)
  [[ -z "${STUB_LANE_FAIL:-}" ]] || exit 1
  ok200 "$STUB_LANE_RUNS"
  ;;
*/actions/workflows/pr-require-checks.yml/runs*)
  [[ -z "${STUB_RUNS_FAIL:-}" ]] || exit 1
  ok200 "$STUB_RUNS"
  ;;
*/actions/runs/*/jobs*) ok200 "$STUB_JOBS" ;;
"api -i repos/o/r/actions/runs/"[0-9]*)
  n=$(grep -c '^api -i repos/o/r/actions/runs/[0-9]*$' "$STUB_LOG")
  total=$(wc -l <<<"$STUB_RUN_SEQ")
  ok200 "$(sed -n "$((n < total ? n : total))p" <<<"$STUB_RUN_SEQ")"
  ;;
"api -X POST "*/rerun)
  [[ -z "${STUB_RERUN_FAIL:-}" ]] || exit 1
  echo '{}'
  ;;
*) exit 1 ;;
esac
EOF
# shellcheck disable=SC2016 # the stub expands $* and $STUB_LOG when it runs
printf '#!/usr/bin/env bash\necho "sleep $*" >>"$STUB_LOG"\n' >"$TMP_ROOT/bin/sleep"
# The clock reads 1000 s past the epoch; any other date call runs the real date.
REAL_DATE="$(command -v date)"
# shellcheck disable=SC2016 # the stub expands its arguments when it runs
printf '#!/usr/bin/env bash\nif [ "$*" = +%%s ]; then echo 1000; else exec %q "$@"; fi\n' "$REAL_DATE" >"$TMP_ROOT/bin/date"
chmod +x "$TMP_ROOT/bin/gh" "$TMP_ROOT/bin/sleep" "$TMP_ROOT/bin/date"

HEAD=0123456789abcdef0123456789abcdef01234567
RCF=.github/workflows/pr-require-checks.yml
CODE=.github/workflows/pr-review-hosted.yml
SEC=.github/workflows/pr-review-security-hosted.yml
# This lane finished at DONE, the other lane at LATER; ci-status started at
# EARLY unless a case says otherwise. AFTER is just past the 60 s margin.
EARLY=2026-10-23T09:50:00Z DONE=2026-10-23T10:00:00Z LATER=2026-10-23T10:05:00Z AFTER=2026-10-23T10:06:01Z
pr() { jq -cn --arg st "${1:-open}" --arg sha "${2:-$HEAD}" '{state: $st, head: {sha: $sha}}'; }
# run <id> [status] [sha] [path] [event] [updated_at] [run_attempt] [head repository]
run() {
  jq -cn --argjson id "$1" --arg st "${2:-completed}" --arg sha "${3:-$HEAD}" --arg p "${4:-$RCF}" --arg ev "${5:-pull_request}" --arg at "${6:-$LATER}" \
    --argjson n "${7:-1}" --arg repo "${8:-o/r}" \
    '{id: $id, status: $st, head_sha: $sha, path: $p, event: $ev, updated_at: $at, run_attempt: $n, head_repository: {full_name: $repo}}'
}
runs() {
  local IFS=,
  printf '{"workflow_runs":[%s]}' "$*"
}
# cijob <status> [started_at]
cijob() { jq -cn --arg st "$1" --arg at "${2:-$EARLY}" '{jobs: [{id: 7, name: "lint-repo", status: "completed"}, {id: 77, name: "ci-status", status: $st, started_at: $at}]}'; }

# The list names one human and one bot; KYLE is the human.
KYLE=153232337 LANES_APP=337595936 STRANGER=9999001
jq -n --argjson h "$KYLE" --argjson b "$LANES_APP" '{version: 1, actors: [{id: $h, login: "kyle-sexton", kind: "human"},
  {id: $b, login: "melodic-automation-lanes[bot]", kind: "bot"}]}' >"$TMP_ROOT/trusted-actors.json"
export STUB_PR STUB_LANE_RUNS STUB_RUNS STUB_JOBS STUB_RUN_SEQ
expect() {
  local label="$1" want_rc="$2" out rc
  : >"$TMP_ROOT/log"
  : >"$TMP_ROOT/out"
  rm -f "$TMP_ROOT/record.json"
  rm -rf "$TMP_ROOT/rt"
  mkdir -p "$TMP_ROOT/rt"
  out="$(PATH="$TMP_ROOT/bin:$PATH" STUB_LOG="$TMP_ROOT/log" GITHUB_REPOSITORY=o/r HEAD_SHA="${HEAD_SHA-$HEAD}" \
    PR_NUMBER="${PR_NUMBER-42}" LANE_PATH="${LANE_PATH-$CODE}" LANE_DONE_AT="${LANE_DONE_AT-$DONE}" \
    GITHUB_OUTPUT="$TMP_ROOT/out" RECORD_FILE="$TMP_ROOT/record.json" GITHUB_RUN_ID=555 \
    REVIEW_ATTEMPT="${REVIEW_ATTEMPT-1}" REVIEW_RERUNNER_ID="${REVIEW_RERUNNER_ID-$KYLE}" \
    TRUSTED_ACTORS="${TRUSTED_ACTORS-$TMP_ROOT/trusted-actors.json}" RUNNER_TEMP="$TMP_ROOT/rt" \
    API_BUDGET_SH="${API_BUDGET_SH-$ROOT/.github/actions/log-api-budget/api-budget.bash}" POLL_SECONDS=60 POLL_LIMIT_SECONDS=600 bash -e "$TMP_ROOT/body.sh" 2>&1)" && rc=0 || rc=$?
  if [[ "$rc" -ne "$want_rc" ]]; then
    fail "$label: expected rc=$want_rc got rc=$rc out='$out'"
  elif [[ -n "${3:-}" && "$out" != *"$3"* ]]; then
    fail "$label: output lacks '$3': '$out'"
  else
    ok "$label"
  fi
}
# check_reran <0|1> <label> [record]: the find step hands the re-run step
# ci-status's job and the record naming the attempt the re-run starts (by
# default run 9's second), or hands it nothing; it never re-runs itself.
check_reran() {
  local want=''
  if [[ "$1" == 1 ]]; then
    want="job-id=77
record=${3:-rerun-ci-status-9-2-$HEAD}"
  fi
  if [[ "$(cat "$TMP_ROOT/out")" == "$want" ]] && ! grep -q '^api -X POST' "$TMP_ROOT/log" &&
    { [[ "$1" == 1 ]] || [[ ! -e "$TMP_ROOT/record.json" ]]; }; then
    ok "$2"
  else
    fail "$2: outputs: $(paste -sd'|' "$TMP_ROOT/out"), posts: $(grep -c '^api -X POST' "$TMP_ROOT/log")"
  fi
}
# The API calls the last case made, against the count its path is pinned to,
# and one rate-limit reading kept for each of them.
check_calls() {
  local n r
  n=$(grep -c '^api ' "$TMP_ROOT/log")
  r=$(grep -c . "$TMP_ROOT/rt/api-budget/github-token" 2>/dev/null)
  if [[ "$n" == "$1" && "$r" == "$1" ]]; then ok "$2 ($1 API calls, $1 readings)"; else fail "$2: $n API calls and $r readings, want $1: $(paste -sd'|' "$TMP_ROOT/log")"; fi
}

# Both lanes finished: the head's last lane re-runs ci-status once.
STUB_PR="$(pr)" STUB_LANE_RUNS="$(runs "$(run 3 completed "$HEAD" "$SEC")")"
STUB_RUNS="$(runs "$(run 5)" "$(run 9)" "$(run 8)")" STUB_JOBS="$(cijob completed)" STUB_RUN_SEQ=''
expect "both lanes finished: a finished run's ci-status is re-run" 0 "Re-running ci-status (job 77) of run 9 on $HEAD as attempt 2."
check_reran 1 "only the ci-status job of the newest run is re-run"
check_calls 4 "the last lane reads the other lane, the runs, the jobs and the PR"
if grep -qxF "api -i repos/o/r/actions/workflows/pr-review-security-hosted.yml/runs?head_sha=$HEAD&event=pull_request&per_page=100" "$TMP_ROOT/log" &&
  grep -qxF "api -i repos/o/r/actions/workflows/pr-require-checks.yml/runs?head_sha=$HEAD&event=pull_request&per_page=100" "$TMP_ROOT/log" &&
  grep -qxF "api -i repos/o/r/actions/runs/9/jobs?filter=latest&per_page=100" "$TMP_ROOT/log"; then
  ok "the other lane's, then the head's pull_request runs and the newest run's latest jobs are read"
else
  fail "unexpected reads: '$(sort -u "$TMP_ROOT/log")'"
fi
STUB_LANE_RUNS="$(runs "$(run 4 completed "$HEAD" "$CODE")")"
LANE_PATH=$SEC expect "the security lane finishing last reads the code lane" 0 "Re-running ci-status (job 77)"
if grep -q '/actions/workflows/pr-review-hosted.yml/runs?' "$TMP_ROOT/log"; then ok "the security lane's run reads the code lane's runs"; else fail "reads: $(paste -sd'|' "$TMP_ROOT/log")"; fi
STUB_RUNS="$(runs "$(run 5)" "$(run 9 completed "${HEAD//0/f}")" "$(run 10 completed "$HEAD" .github/workflows/other.yml)" "$(run 11 completed "$HEAD" "$RCF" merge_group)")"
expect "runs on another head, of another file or event are not the newest" 0 "of run 5 on $HEAD"
STUB_RUNS="$(runs "$(run 9)" "$(run 12 completed "$HEAD" "$RCF" pull_request "$LATER" 1 someone/fork)")"
expect "a fork's run at the same head is not the newest" 0 "of run 9 on $HEAD"
STUB_LANE_RUNS="$(runs "$(run 3 completed "$HEAD" "$SEC")" "$(run 6 in_progress "$HEAD" "$SEC" pull_request "$LATER" 1 someone/fork)")"
expect "a fork's other-lane run still going does not hold the re-run" 0 "Re-running ci-status (job 77) of run 9"
STUB_LANE_RUNS="$(runs "$(run 3 completed "$HEAD" "$SEC")")"
STUB_RUNS="$(runs "$(run 9)")"

# The other lane still going: no re-run, one API call; its completion re-runs ci-status.
for st in in_progress queued waiting; do
  STUB_LANE_RUNS="$(runs "$(run 2 completed "$HEAD" "$SEC")" "$(run 3 "$st" "$HEAD" "$SEC")")"
  expect "the other lane's newest run $st: left for its completion" 0 "pr-review-security-hosted.yml has not finished on $HEAD; its completion re-runs ci-status."
  check_reran 0 "nothing is re-run while the other lane is $st"
  check_calls 1 "the first lane to finish stops after one read"
done
STUB_LANE_RUNS="$(runs "$(run 3 in_progress "${HEAD//0/f}" "$SEC")" "$(run 4 in_progress "$HEAD" "$SEC" merge_group)" "$(run 5 in_progress "$HEAD" "$CODE")")"
expect "other heads, events or files are not the other lane's newest run" 0 "Re-running ci-status (job 77)"
check_reran 1 "a head with no other-lane run of its own is re-run"
STUB_LANE_RUNS="$(runs "$(run 3 in_progress "$HEAD" "$SEC")" "$(run 4 completed "$HEAD" "$SEC")")"
expect "an older other-lane run still going does not hold the newest, finished one" 0 "Re-running ci-status (job 77)"
check_reran 1 "only the other lane's newest run decides"

# One lane only on the head (an exempt author, a lane that never ran), or the
# other lane skipped, cancelled or failed: this lane is the last, so re-run.
STUB_LANE_RUNS="$(runs)"
expect "no run of the other lane: re-run on this lane alone" 0 "Re-running ci-status (job 77) of run 9"
check_reran 1 "a single-lane head is re-run"
check_calls 4 "a single-lane head costs the same as the last lane"
for c in skipped cancelled failure; do
  STUB_LANE_RUNS="$(runs "$(jq -c --arg c "$c" '. + {conclusion: $c}' <<<"$(run 3 completed "$HEAD" "$SEC")")")"
  expect "the other lane completed $c counts as finished" 0 "Re-running ci-status (job 77)"
  check_reran 1 "the other lane $c: re-run"
done
STUB_LANE_RUNS="$(runs "$(run 3 completed "$HEAD" "$SEC")")"

# ci-status that already read both finished lanes is left alone.
STUB_JOBS="$(cijob completed "$AFTER")"
expect "a ci-status that started after both lanes finished is left alone" 0 "started at $AFTER, after both lanes finished ($LATER)"
check_reran 0 "a fresh ci-status is not re-run"
check_calls 3 "a fresh ci-status costs no PR read and no re-run"
STUB_JOBS="$(cijob completed 2026-10-23T10:03:00Z)"
expect "a ci-status that started between the lanes is re-run" 0 "Re-running ci-status (job 77)"
STUB_LANE_RUNS="$(runs "$(run 3 completed "$HEAD" "$SEC" pull_request 2026-10-23T09:40:00Z)")" STUB_JOBS="$(cijob completed 2026-10-23T09:55:00Z)"
expect "a ci-status that started before this lane finished is re-run" 0 "Re-running ci-status (job 77)"
STUB_LANE_RUNS="$(runs "$(run 3 completed "$HEAD" "$SEC")")" STUB_JOBS="$(cijob completed "$LATER")"
expect "a ci-status that started the second the last lane finished is re-run" 0 "Re-running ci-status (job 77)"
STUB_JOBS="$(cijob completed 2026-10-23T10:06:00Z)"
expect "a ci-status that started within 60 s of the last lane is re-run" 0 "Re-running ci-status (job 77)"
STUB_JOBS="$(cijob completed "$AFTER")" STUB_LANE_RUNS="$(runs "$(run 3 completed "$HEAD" "$SEC" pull_request 2026-10-23T10:05)")"
expect "an unreadable finish time of the other lane means a re-run" 0 "Re-running ci-status (job 77)"
STUB_LANE_RUNS="$(runs "$(run 3 completed "$HEAD" "$SEC")")"
STUB_RUNS="$(runs "$(run 9 queued)")" STUB_JOBS="$(cijob queued "")"
expect "a ci-status re-run already queued is left alone" 0 "ci-status of run 9 has not started"
check_reran 0 "the second of two racing lanes adds no re-run"
check_calls 3 "a queued ci-status costs no PR read"
STUB_JOBS="$(cijob in_progress "$AFTER")" STUB_RUNS="$(runs "$(run 9 in_progress)")"
expect "a ci-status in progress that started after both lanes is left alone" 0 "after both lanes finished"
if grep -q '^sleep' "$TMP_ROOT/log"; then fail "a fresh ci-status was polled"; else ok "a fresh ci-status in progress is not polled"; fi

# A stale ci-status in progress waits for its run, reading only the run.
STUB_RUNS="$(runs "$(run 9 in_progress)")" STUB_JOBS="$(cijob in_progress)"
STUB_RUN_SEQ="$(run 9 in_progress)
$(run 9)"
expect "a ci-status in progress is polled, then re-run once its run finishes" 0 "Re-running ci-status (job 77) of run 9"
check_reran 1 "the polled run's ci-status is re-run once"
if [[ "$(grep -c '^sleep 60$' "$TMP_ROOT/log")" == 2 ]]; then ok "it polled every 60 s"; else fail "polls: $(grep '^sleep' "$TMP_ROOT/log" | paste -sd'|')"; fi
check_calls 6 "each poll reads the run only"
if [[ "$(grep -c '/jobs?' "$TMP_ROOT/log")" == 1 ]]; then ok "the job list is read once"; else fail "job list reads: $(grep -c '/jobs?' "$TMP_ROOT/log")"; fi
# A poll read again is a conditional GET: a 304 stands for the last 200's
# body, so the run still reads in progress, and the polls keep their 60 s pace.
echo 2 >"$TMP_ROOT/not-modified"
STUB_ETAG='W/"e1"' STUB_NOT_MODIFIED_FILE="$TMP_ROOT/not-modified" \
  expect "a poll answered 304 reads the run as last read, then re-runs once it finishes" 0 "Re-running ci-status (job 77) of run 9 on $HEAD as attempt 2."
check_reran 1 "the conditionally polled run's ci-status is re-run once"
if [[ "$(grep -c '^sleep 60$' "$TMP_ROOT/log")" == 4 && "$(grep -c '^sleep' "$TMP_ROOT/log")" == 4 ]]; then ok "two 304s cost two 60 s polls and no retry"; else fail "sleeps: $(grep '^sleep' "$TMP_ROOT/log" | paste -sd'|')"; fi
check_calls 8 "each poll still sends one read"
if [[ "$(grep -c "If-None-Match: W/\"e1\"" "$TMP_ROOT/log")" == 3 && "$(grep -c '^304 ' "$TMP_ROOT/rt/api-budget/github-token")" == 2 ]]; then
  ok "every repeat poll is conditional, and each 304 keeps its reading"
else
  fail "conditional reads: $(grep -c 'If-None-Match' "$TMP_ROOT/log"), 304 readings: $(grep -c '^304 ' "$TMP_ROOT/rt/api-budget/github-token")"
fi
STUB_RUN_SEQ="$(run 9 in_progress)"
expect "a run still going after the limit fails" 1 "::error::run 9 on $HEAD has not finished after 600s"
check_reran 0 "nothing is re-run past the poll limit"
if [[ "$(grep -c '^sleep 60$' "$TMP_ROOT/log")" == 10 ]]; then ok "it stops after 10 minutes of polls"; else fail "polls: $(grep -c '^sleep 60$' "$TMP_ROOT/log")"; fi
check_calls 13 "a 10-minute wait reads the run 10 times"
for st in queued waiting pending; do
  STUB_JOBS="$(cijob "$st" "")"
  expect "a ci-status $st is left to read the reviews when it starts" 0 "ci-status of run 9 has not started"
  check_reran 0 "a $st ci-status is not re-run"
done
STUB_JOBS='{"jobs":[]}'
expect "a run with no ci-status job listed yet is left alone" 0 "has not started"
STUB_RUNS="$(runs "$(run 9)")"
expect "a finished run with no ci-status job fails" 1 "::error::run 9 on $HEAD has no ci-status job to re-run."

STUB_RUNS="$(runs)" STUB_JOBS="$(cijob completed)"
expect "no run on the head yet is left alone" 0 "No pr-require-checks run on $HEAD yet"
check_reran 0 "nothing is re-run with no run"
STUB_RUNS="$(runs "$(run 9)")"

STUB_PR="$(pr closed)"
expect "a closed PR is left alone" 0 "#42 is closed or no longer at $HEAD"
check_reran 0 "a closed PR's ci-status is not re-run"
STUB_PR="$(pr open "${HEAD//0/f}")"
expect "a head the PR moved past is left alone" 0 "no longer at $HEAD"
check_reran 0 "a moved head's ci-status is not re-run"
STUB_PR="$(pr)"
PR_NUMBER='' expect "a review run with no pull request is left alone" 0 "names no pull request"
if [[ -s "$TMP_ROOT/log" ]]; then fail "a run with no pull request read the API"; else ok "a run with no pull request reads nothing"; fi
PR_NUMBER='1;id' expect "a pull request number that is not a number is left alone" 0 "names no pull request"
HEAD_SHA=main expect "a head that is not a commit SHA fails" 1 "::error::the review run's head 'main' is not a commit SHA."
LANE_PATH=.github/workflows/pr-verify.yml expect "a run of another file fails" 1 "::error::'.github/workflows/pr-verify.yml' is not a review lane."
LANE_DONE_AT='2026-10-23 10:00' expect "a finish time that is not a UTC timestamp fails" 1 "is not a UTC timestamp."
if [[ -s "$TMP_ROOT/log" ]]; then fail "a bad finish time read the API"; else ok "a bad finish time reads nothing"; fi

# A primary rate limit waits for its reset inside the cap, then reads again.
export STUB_LIMIT_FILE="$TMP_ROOT/limit" STUB_RESET=1119
STUB_PR="$(pr)" STUB_LANE_RUNS="$(runs "$(run 3 completed "$HEAD" "$SEC")")" STUB_RUNS="$(runs "$(run 9)")" STUB_JOBS="$(cijob completed)"
echo 1 >"$STUB_LIMIT_FILE"
expect "a rate-limited read waits for the reset, then re-runs" 0 "Rate limited reading the pr-require-checks runs on $HEAD; waiting 120s for the reset."
check_reran 1 "the read after the reset goes on to the re-run"
if [[ "$(grep -c '^sleep 120$' "$TMP_ROOT/log")" == 1 ]]; then ok "it slept until one second past the reset"; else fail "sleeps: $(grep '^sleep' "$TMP_ROOT/log" | paste -sd'|')"; fi
check_calls 5 "the refused read is counted and its reading kept"
if grep -qx '403 na 0 na 1119 na' "$TMP_ROOT/rt/api-budget/github-token"; then ok "the refusal's reading names its status and reset"; else fail "readings: $(paste -sd'|' "$TMP_ROOT/rt/api-budget/github-token")"; fi
echo 1 >"$STUB_LIMIT_FILE"
STUB_RETRY_AFTER=30 expect "a retry-after refusal waits that many seconds" 0 "waiting 30s for the reset."
check_reran 1 "the read after retry-after goes on to the re-run"
echo 1 >"$STUB_LIMIT_FILE"
STUB_RESET=1700 expect "a reset past the cap fails, naming the reset" 1 "::error::the token's rate limit blocks reading the pr-require-checks runs on $HEAD until"
check_reran 0 "nothing is re-run when the reset is past the cap"
if grep -q '^sleep' "$TMP_ROOT/log"; then fail "it waited for a reset past the cap"; else ok "a reset past the cap is not waited for"; fi
echo 1 >"$STUB_LIMIT_FILE"
STUB_RUNS="$(runs "$(run 9 in_progress)")" STUB_JOBS="$(cijob in_progress)" STUB_RUN_SEQ="$(run 9 in_progress)"
expect "the reset wait counts toward the poll cap" 1 "has not finished after 600s"
if [[ "$(grep -c '^sleep 60$' "$TMP_ROOT/log")" == 8 ]]; then ok "a 120 s reset wait leaves 8 polls"; else fail "polls: $(grep -c '^sleep 60$' "$TMP_ROOT/log")"; fi
unset STUB_LIMIT_FILE STUB_RESET
STUB_RUNS="$(runs "$(run 9)")" STUB_JOBS="$(cijob completed)"

export STUB_LANE_FAIL=1
expect "an unreadable other-lane run list fails" 1 "::error::could not read the pr-review-security-hosted.yml runs on $HEAD; re-run this run."
unset STUB_LANE_FAIL
export STUB_RUNS_FAIL=1
expect "an unreadable run list fails" 1 "::error::could not read the pr-require-checks runs on $HEAD; re-run this run."
unset STUB_RUNS_FAIL
# The record names the run, the attempt the re-run starts and the head, and
# carries the PR, the job, the lane and the reason.
STUB_RUNS="$(runs "$(run 9 completed "$HEAD" "$RCF" pull_request "$LATER" 2)")"
expect "a run at attempt 2 is re-run as attempt 3" 0 "Re-running ci-status (job 77) of run 9 on $HEAD as attempt 3."
check_reran 1 "the record names attempt 3" "rerun-ci-status-9-3-$HEAD"
want_record="$(jq -cn --arg h "$HEAD" --arg l "$CODE" '{recorder_run_id: 555, run_id: 9, attempt: 3, head_sha: $h, pr_number: 42,
  job_id: 77, lane_path: $l, reason: "the review lanes finished after ci-status read them"}')"
if [[ "$(jq -c . "$TMP_ROOT/record.json")" == "$want_record" ]]; then ok "the record file binds run, attempt, head and reason"; else fail "record: $(cat "$TMP_ROOT/record.json")"; fi
STUB_RUNS="$(runs "$(run 9 in_progress)")" STUB_JOBS="$(cijob in_progress)"
STUB_RUN_SEQ="$(run 9 completed "$HEAD" "$RCF" pull_request "$LATER" 4)"
expect "a polled run names the attempt read after its poll" 0 "as attempt 5."
check_reran 1 "the polled run's record names its attempt then" "rerun-ci-status-9-5-$HEAD"
STUB_RUNS="$(runs "$(jq -c 'del(.run_attempt)' <<<"$(run 9)")")" STUB_JOBS="$(cijob completed)" STUB_RUN_SEQ=''
expect "a run with no attempt number fails" 1 "::error::run 9 on $HEAD reports no attempt number."
check_reran 0 "nothing is handed on without an attempt number"
STUB_RUNS="$(runs "$(run 9)")"

# A review run re-run by someone not listed as a human leaves no record, so
# pr-verify's gate refuses the ci-status attempt it causes; ci-status is
# still re-run. A first attempt, or a listed human's re-run, is recorded. An
# unreadable list, or an attempt or re-runner that is not a number, records
# nothing.
# check_unrecorded <label>: the re-run step gets the job and no record.
check_unrecorded() {
  if [[ "$(cat "$TMP_ROOT/out")" == "job-id=77" && ! -e "$TMP_ROOT/record.json" ]]; then
    ok "$1"
  else
    fail "$1: outputs: $(paste -sd'|' "$TMP_ROOT/out"), record file: $([[ -e "$TMP_ROOT/record.json" ]] && echo yes || echo no)"
  fi
}
REVIEW_ATTEMPT=2 REVIEW_RERUNNER_ID=$KYLE expect "a review run a listed human re-ran is recorded" 0 "Re-running ci-status (job 77) of run 9 on $HEAD as attempt 2."
check_reran 1 "a listed human's review re-run hands on the record"
REVIEW_ATTEMPT=2 REVIEW_RERUNNER_ID=$STRANGER expect "a review run an unlisted user re-ran is not recorded" 0 "::notice::review attempt 2 was started by $STRANGER"
check_unrecorded "an unlisted re-runner's review re-run hands on the job and no record"
REVIEW_ATTEMPT=3 REVIEW_RERUNNER_ID=$LANES_APP expect "a review run a listed bot re-ran is not recorded" 0 "is not a listed human"
check_unrecorded "a bot re-runner's review re-run hands on no record"
REVIEW_ATTEMPT=2 REVIEW_RERUNNER_ID=$KYLE TRUSTED_ACTORS="$TMP_ROOT/absent.json" expect "an unreadable list records nothing" 0 "is not a listed human"
check_unrecorded "an unreadable list hands on no record"
printf '{"actors": [' >"$TMP_ROOT/broken.json"
REVIEW_ATTEMPT=2 REVIEW_RERUNNER_ID=$KYLE TRUSTED_ACTORS="$TMP_ROOT/broken.json" expect "a list that does not parse records nothing" 0 "is not a listed human"
check_unrecorded "a broken list hands on no record"
REVIEW_ATTEMPT=2 REVIEW_RERUNNER_ID='' expect "a re-run with no re-runner id records nothing" 0 "is not a listed human"
check_unrecorded "a missing re-runner id hands on no record"
REVIEW_ATTEMPT='' REVIEW_RERUNNER_ID=$KYLE expect "a review run with no attempt number records nothing" 0 "is not a listed human"
check_unrecorded "a missing review attempt hands on no record"
REVIEW_ATTEMPT=1 REVIEW_RERUNNER_ID=$STRANGER TRUSTED_ACTORS="$TMP_ROOT/absent.json" expect "a first review attempt is recorded without the list" 0 "as attempt 2."
check_reran 1 "a first attempt hands on the record"

# Without the library (a failed checkout) the job runs as before and keeps no reading.
STUB_PR="$(pr)" STUB_LANE_RUNS="$(runs "$(run 3 completed "$HEAD" "$SEC")")" STUB_RUNS="$(runs "$(run 9)")" STUB_JOBS="$(cijob completed)"
REVIEW_ATTEMPT=1 API_BUDGET_SH="$TMP_ROOT/absent.bash" expect "a missing api-budget library still re-runs" 0 "Re-running ci-status (job 77) of run 9"
check_reran 1 "the re-run is handed on without the library"
if [[ ! -e "$TMP_ROOT/rt/api-budget/github-token" ]]; then ok "no reading is kept without the library"; else fail "readings kept without the library"; fi

# The re-run step re-runs only a job id, once.
rerun_expect() {
  local label="$1" want_rc="$2" out rc
  : >"$TMP_ROOT/log"
  out="$(PATH="$TMP_ROOT/bin:$PATH" STUB_LOG="$TMP_ROOT/log" GITHUB_REPOSITORY=o/r JOB_ID="$3" bash -e "$TMP_ROOT/rerun.sh" 2>&1)" && rc=0 || rc=$?
  if [[ "$rc" -ne "$want_rc" ]]; then fail "$label: expected rc=$want_rc got rc=$rc out='$out'"; else ok "$label"; fi
}
rerun_expect "the re-run step re-runs the found job" 0 77
if [[ "$(cat "$TMP_ROOT/log")" == 'api -X POST repos/o/r/actions/jobs/77/rerun' ]]; then ok "it posts one re-run of job 77"; else fail "posts: $(paste -sd'|' "$TMP_ROOT/log")"; fi
rerun_expect "a job id that is not a number fails" 1 '77/../x'
if [[ -s "$TMP_ROOT/log" ]]; then fail "a bad job id reached the API"; else ok "a bad job id reaches no API"; fi
export STUB_RERUN_FAIL=1
rerun_expect "a refused re-run fails the job" 1 77
unset STUB_RERUN_FAIL

test_harness::report
