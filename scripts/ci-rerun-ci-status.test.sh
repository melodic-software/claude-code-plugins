#!/usr/bin/env bash
# Runs the `Re-run ci-status on the reviewed head` step body of
# .github/workflows/pr-feedback-dispatch.yml's rerun-ci-status job under the
# shell Actions gives a step with no `shell:` (bash -e), against stub `gh` and
# `sleep`.
#
# When a review run completes and the other lane's newest run on the head has
# finished or never ran, the job re-runs only the ci-status job of the newest
# pr-require-checks pull_request run on the reviewed head, after that run
# finishes, polling at most POLL_LIMIT_SECONDS. The other lane still going, a
# closed PR, a moved head, no run yet, a ci-status not started or one started
# after both lanes finished is left alone. A rate limit waits for its reset
# within the cap, or fails past it. Unreadable reads fail. Each
# path's API call count is pinned.
# test-scope: .github/workflows/pr-feedback-dispatch.yml
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORKFLOW="$ROOT/.github/workflows/pr-feedback-dispatch.yml"

# shellcheck source=lib/test-harness.sh
. "$ROOT/scripts/lib/test-harness.sh"

TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT

NAME='Re-run ci-status on the reviewed head'
step="$(awk -v name="      - name: $NAME" '$0 == name { on = 1; print; next }
  on && /^      - / { exit }
  on && /^  [a-z]/ { exit }
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
# shellcheck disable=SC2016 # the ${{ }} text is workflow source, not shell
for env in 'HEAD_SHA: ${{ github.event.workflow_run.head_sha }}' 'PR_NUMBER: ${{ github.event.workflow_run.pull_requests[0].number }}' \
  'LANE_PATH: ${{ github.event.workflow_run.path }}' 'LANE_DONE_AT: ${{ github.event.workflow_run.updated_at }}' "POLL_LIMIT_SECONDS: '600'"; do
  if [[ "$step" == *"$env"* ]]; then ok "step env carries $env"; else fail "step env lacks $env"; fi
done
job="$(awk '/^  rerun-ci-status:$/ { on = 1; next } on && /^  [a-z]/ { exit } on { print }' "$WORKFLOW")"
if [[ "$job" == *$'    permissions:\n      actions: write # '*$'\n      pull-requests: read # '* && "$job" != *"contents:"* ]]; then
  ok "the job holds actions: write and pull-requests: read only"
else
  fail "the job's permissions changed"
fi

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
# run <id> [status] [sha] [path] [event] [updated_at]
run() {
  jq -cn --argjson id "$1" --arg st "${2:-completed}" --arg sha "${3:-$HEAD}" --arg p "${4:-$RCF}" --arg ev "${5:-pull_request}" --arg at "${6:-$LATER}" \
    '{id: $id, status: $st, head_sha: $sha, path: $p, event: $ev, updated_at: $at}'
}
runs() {
  local IFS=,
  printf '{"workflow_runs":[%s]}' "$*"
}
# cijob <status> [started_at]
cijob() { jq -cn --arg st "$1" --arg at "${2:-$EARLY}" '{jobs: [{id: 7, name: "lint-repo", status: "completed"}, {id: 77, name: "ci-status", status: $st, started_at: $at}]}'; }

export STUB_PR STUB_LANE_RUNS STUB_RUNS STUB_JOBS STUB_RUN_SEQ
expect() {
  local label="$1" want_rc="$2" out rc
  : >"$TMP_ROOT/log"
  out="$(PATH="$TMP_ROOT/bin:$PATH" STUB_LOG="$TMP_ROOT/log" GITHUB_REPOSITORY=o/r HEAD_SHA="${HEAD_SHA-$HEAD}" \
    PR_NUMBER="${PR_NUMBER-42}" LANE_PATH="${LANE_PATH-$CODE}" LANE_DONE_AT="${LANE_DONE_AT-$DONE}" \
    POLL_SECONDS=60 POLL_LIMIT_SECONDS=600 bash -e "$TMP_ROOT/body.sh" 2>&1)" && rc=0 || rc=$?
  if [[ "$rc" -ne "$want_rc" ]]; then
    fail "$label: expected rc=$want_rc got rc=$rc out='$out'"
  elif [[ -n "${3:-}" && "$out" != *"$3"* ]]; then
    fail "$label: output lacks '$3': '$out'"
  else
    ok "$label"
  fi
}
reran() { grep -c '^api -X POST ' "$TMP_ROOT/log"; }
check_reran() {
  if [[ "$(reran)" == "$1" ]] && { [[ "$1" == 0 ]] || grep -qxF 'api -X POST repos/o/r/actions/jobs/77/rerun' "$TMP_ROOT/log"; }; then
    ok "$2"
  else
    fail "$2: re-runs: $(grep '^api -X POST' "$TMP_ROOT/log" | paste -sd'|')"
  fi
}
# The API calls the last case made, against the count its path is pinned to.
check_calls() {
  local n
  n=$(grep -c '^api ' "$TMP_ROOT/log")
  if [[ "$n" == "$1" ]]; then ok "$2 ($1 API calls)"; else fail "$2: $n API calls, want $1: $(paste -sd'|' "$TMP_ROOT/log")"; fi
}

# Both lanes finished: the head's last lane re-runs ci-status once.
STUB_PR="$(pr)" STUB_LANE_RUNS="$(runs "$(run 3 completed "$HEAD" "$SEC")")"
STUB_RUNS="$(runs "$(run 5)" "$(run 9)" "$(run 8)")" STUB_JOBS="$(cijob completed)" STUB_RUN_SEQ=''
expect "both lanes finished: a finished run's ci-status is re-run" 0 "Re-ran ci-status (job 77) of run 9 on $HEAD."
check_reran 1 "only the ci-status job of the newest run is re-run"
check_calls 5 "the last lane reads the other lane, the runs, the jobs and the PR, then re-runs"
if grep -qxF "api -i repos/o/r/actions/workflows/pr-review-security-hosted.yml/runs?head_sha=$HEAD&event=pull_request&per_page=100" "$TMP_ROOT/log" &&
  grep -qxF "api -i repos/o/r/actions/workflows/pr-require-checks.yml/runs?head_sha=$HEAD&event=pull_request&per_page=100" "$TMP_ROOT/log" &&
  grep -qxF "api -i repos/o/r/actions/runs/9/jobs?filter=latest&per_page=100" "$TMP_ROOT/log"; then
  ok "the other lane's, then the head's pull_request runs and the newest run's latest jobs are read"
else
  fail "unexpected reads: '$(sort -u "$TMP_ROOT/log")'"
fi
STUB_LANE_RUNS="$(runs "$(run 4 completed "$HEAD" "$CODE")")"
LANE_PATH=$SEC expect "the security lane finishing last reads the code lane" 0 "Re-ran ci-status (job 77)"
if grep -q '/actions/workflows/pr-review-hosted.yml/runs?' "$TMP_ROOT/log"; then ok "the security lane's run reads the code lane's runs"; else fail "reads: $(paste -sd'|' "$TMP_ROOT/log")"; fi
STUB_RUNS="$(runs "$(run 5)" "$(run 9 completed "${HEAD//0/f}")" "$(run 10 completed "$HEAD" .github/workflows/other.yml)" "$(run 11 completed "$HEAD" "$RCF" merge_group)")"
expect "runs on another head, of another file or event are not the newest" 0 "of run 5 on $HEAD"
STUB_RUNS="$(runs "$(run 9)")"

# The other lane still going: no re-run, one API call; its completion re-runs ci-status.
for st in in_progress queued waiting; do
  STUB_LANE_RUNS="$(runs "$(run 2 completed "$HEAD" "$SEC")" "$(run 3 "$st" "$HEAD" "$SEC")")"
  expect "the other lane's newest run $st: left for its completion" 0 "pr-review-security-hosted.yml has not finished on $HEAD; its completion re-runs ci-status."
  check_reran 0 "nothing is re-run while the other lane is $st"
  check_calls 1 "the first lane to finish stops after one read"
done
STUB_LANE_RUNS="$(runs "$(run 3 in_progress "${HEAD//0/f}" "$SEC")" "$(run 4 in_progress "$HEAD" "$SEC" merge_group)" "$(run 5 in_progress "$HEAD" "$CODE")")"
expect "other heads, events or files are not the other lane's newest run" 0 "Re-ran ci-status (job 77)"
STUB_LANE_RUNS="$(runs "$(run 3 in_progress "$HEAD" "$SEC")" "$(run 4 completed "$HEAD" "$SEC")")"
expect "an older other-lane run still going does not hold the newest, finished one" 0 "Re-ran ci-status (job 77)"
check_reran 1 "only the other lane's newest run decides"
check_reran 1 "a head with no other-lane run of its own is re-run"

# One lane only on the head (an exempt author, a lane that never ran), or the
# other lane skipped, cancelled or failed: this lane is the last, so re-run.
STUB_LANE_RUNS="$(runs)"
expect "no run of the other lane: re-run on this lane alone" 0 "Re-ran ci-status (job 77) of run 9"
check_reran 1 "a single-lane head is re-run"
check_calls 5 "a single-lane head costs the same as the last lane"
for c in skipped cancelled failure; do
  STUB_LANE_RUNS="$(runs "$(jq -c --arg c "$c" '. + {conclusion: $c}' <<<"$(run 3 completed "$HEAD" "$SEC")")")"
  expect "the other lane completed $c counts as finished" 0 "Re-ran ci-status (job 77)"
  check_reran 1 "the other lane $c: re-run"
done
STUB_LANE_RUNS="$(runs "$(run 3 completed "$HEAD" "$SEC")")"

# ci-status that already read both finished lanes is left alone.
STUB_JOBS="$(cijob completed "$AFTER")"
expect "a ci-status that started after both lanes finished is left alone" 0 "started at $AFTER, after both lanes finished ($LATER)"
check_reran 0 "a fresh ci-status is not re-run"
check_calls 3 "a fresh ci-status costs no PR read and no re-run"
STUB_JOBS="$(cijob completed 2026-10-23T10:03:00Z)"
expect "a ci-status that started between the lanes is re-run" 0 "Re-ran ci-status (job 77)"
STUB_LANE_RUNS="$(runs "$(run 3 completed "$HEAD" "$SEC" pull_request 2026-10-23T09:40:00Z)")" STUB_JOBS="$(cijob completed 2026-10-23T09:55:00Z)"
expect "a ci-status that started before this lane finished is re-run" 0 "Re-ran ci-status (job 77)"
STUB_LANE_RUNS="$(runs "$(run 3 completed "$HEAD" "$SEC")")" STUB_JOBS="$(cijob completed "$LATER")"
expect "a ci-status that started the second the last lane finished is re-run" 0 "Re-ran ci-status (job 77)"
STUB_JOBS="$(cijob completed 2026-10-23T10:06:00Z)"
expect "a ci-status that started within 60 s of the last lane is re-run" 0 "Re-ran ci-status (job 77)"
STUB_JOBS="$(cijob completed "$AFTER")" STUB_LANE_RUNS="$(runs "$(run 3 completed "$HEAD" "$SEC" pull_request 2026-10-23T10:05)")"
expect "an unreadable finish time of the other lane means a re-run" 0 "Re-ran ci-status (job 77)"
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
expect "a ci-status in progress is polled, then re-run once its run finishes" 0 "Re-ran ci-status (job 77) of run 9"
check_reran 1 "the polled run's ci-status is re-run once"
if [[ "$(grep -c '^sleep 60$' "$TMP_ROOT/log")" == 2 ]]; then ok "it polled every 60 s"; else fail "polls: $(grep '^sleep' "$TMP_ROOT/log" | paste -sd'|')"; fi
check_calls 7 "each poll reads the run only"
if [[ "$(grep -c '/jobs?' "$TMP_ROOT/log")" == 1 ]]; then ok "the job list is read once"; else fail "job list reads: $(grep -c '/jobs?' "$TMP_ROOT/log")"; fi
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
export STUB_RERUN_FAIL=1
expect "a refused re-run fails the job" 1
unset STUB_RERUN_FAIL

test_harness::report
