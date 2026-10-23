#!/usr/bin/env bash
# Runs the `Re-run ci-status on the reviewed head` step body of
# .github/workflows/pr-feedback-dispatch.yml's rerun-ci-status job under the
# shell Actions gives a step with no `shell:` (bash -e), against stub `gh` and
# `sleep`.
#
# When a review run completes, the job re-runs only the ci-status job of the
# newest pr-require-checks pull_request run on the reviewed head, after that
# run finishes, polling at most POLL_LIMIT_SECONDS. A closed PR, a moved head,
# no run yet or a ci-status not started is left alone. Unreadable reads fail.
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
for env in 'HEAD_SHA: ${{ github.event.workflow_run.head_sha }}' 'PR_NUMBER: ${{ github.event.workflow_run.pull_requests[0].number }}' "POLL_LIMIT_SECONDS: '1740'"; do
  if [[ "$step" == *"$env"* ]]; then ok "step env carries $env"; else fail "step env lacks $env"; fi
done
job="$(awk '/^  rerun-ci-status:$/ { on = 1; next } on && /^  [a-z]/ { exit } on { print }' "$WORKFLOW")"
if [[ "$job" == *$'    permissions:\n      actions: write # '*$'\n      pull-requests: read # '* && "$job" != *"contents:"* ]]; then
  ok "the job holds actions: write and pull-requests: read only"
else
  fail "the job's permissions changed"
fi

# The stub logs its arguments. A pulls read prints STUB_PR. A runs read prints
# the next line of STUB_RUNS_SEQ (the last line once used up), failing when
# STUB_RUNS_FAIL is set. A jobs read prints STUB_JOBS. A POST re-run fails when
# STUB_RERUN_FAIL is set. The sleep stub logs its seconds.
mkdir -p "$TMP_ROOT/bin"
cat >"$TMP_ROOT/bin/gh" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$STUB_LOG"
case "$*" in
*/pulls/*) printf '%s\n' "$STUB_PR" ;;
*/actions/workflows/pr-require-checks.yml/runs*)
  [[ -z "${STUB_RUNS_FAIL:-}" ]] || exit 1
  n=$(grep -c '/runs?' "$STUB_LOG")
  total=$(wc -l <<<"$STUB_RUNS_SEQ")
  sed -n "$((n < total ? n : total))p" <<<"$STUB_RUNS_SEQ"
  ;;
*/actions/runs/*/jobs*) printf '%s\n' "$STUB_JOBS" ;;
"api -X POST "*/rerun)
  [[ -z "${STUB_RERUN_FAIL:-}" ]] || exit 1
  echo '{}'
  ;;
*) exit 1 ;;
esac
EOF
# shellcheck disable=SC2016 # the stub expands $* and $STUB_LOG when it runs
printf '#!/usr/bin/env bash\necho "sleep $*" >>"$STUB_LOG"\n' >"$TMP_ROOT/bin/sleep"
chmod +x "$TMP_ROOT/bin/gh" "$TMP_ROOT/bin/sleep"

HEAD=0123456789abcdef0123456789abcdef01234567
RCF=.github/workflows/pr-require-checks.yml
pr() { jq -cn --arg st "${1:-open}" --arg sha "${2:-$HEAD}" '{state: $st, head: {sha: $sha}}'; }
# run <id> [status] [sha] [path] [event]
run() { jq -cn --argjson id "$1" --arg st "${2:-completed}" --arg sha "${3:-$HEAD}" --arg p "${4:-$RCF}" --arg ev "${5:-pull_request}" \
  '{id: $id, status: $st, head_sha: $sha, path: $p, event: $ev}'; }
runs() { local IFS=,; printf '{"workflow_runs":[%s]}' "$*"; }
cijob() { jq -cn --arg st "$1" '{jobs: [{id: 7, name: "lint-repo", status: "completed"}, {id: 77, name: "ci-status", status: $st}]}'; }

export STUB_PR STUB_RUNS_SEQ STUB_JOBS
expect() {
  local label="$1" want_rc="$2" out rc
  : >"$TMP_ROOT/log"
  out="$(PATH="$TMP_ROOT/bin:$PATH" STUB_LOG="$TMP_ROOT/log" GITHUB_REPOSITORY=o/r HEAD_SHA="${HEAD_SHA-$HEAD}" \
    PR_NUMBER="${PR_NUMBER-42}" POLL_SECONDS=60 POLL_LIMIT_SECONDS=600 bash -e "$TMP_ROOT/body.sh" 2>&1)" && rc=0 || rc=$?
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

STUB_PR="$(pr)" STUB_RUNS_SEQ="$(runs "$(run 5)" "$(run 9)" "$(run 8)")" STUB_JOBS="$(cijob completed)"
expect "a finished run's ci-status is re-run" 0 "Re-ran ci-status (job 77) of run 9 on $HEAD."
check_reran 1 "only the ci-status job of the newest run is re-run"
if grep -qxF "api repos/o/r/actions/workflows/pr-require-checks.yml/runs?head_sha=$HEAD&event=pull_request&per_page=100" "$TMP_ROOT/log" &&
  grep -qxF "api repos/o/r/actions/runs/9/jobs?filter=latest&per_page=100" "$TMP_ROOT/log"; then
  ok "the head's pull_request runs and the newest run's latest jobs are read"
else
  fail "unexpected reads: '$(sort -u "$TMP_ROOT/log")'"
fi
STUB_RUNS_SEQ="$(runs "$(run 5)" "$(run 9 completed "${HEAD//0/f}")" "$(run 10 completed "$HEAD" .github/workflows/other.yml)" "$(run 11 completed "$HEAD" "$RCF" merge_group)")"
expect "runs on another head, of another file or event are not the newest" 0 "of run 5 on $HEAD"

STUB_RUNS_SEQ="$(runs "$(run 9 in_progress)")
$(runs "$(run 9 in_progress)")
$(runs "$(run 9)")" STUB_JOBS="$(cijob in_progress)"
expect "a ci-status in progress is polled, then re-run once its run finishes" 0 "Re-ran ci-status (job 77) of run 9"
check_reran 1 "the polled run's ci-status is re-run once"
if [[ "$(grep -c '^sleep 60$' "$TMP_ROOT/log")" == 2 ]]; then ok "it polled every 60 s"; else fail "polls: $(grep '^sleep' "$TMP_ROOT/log" | paste -sd'|')"; fi
STUB_RUNS_SEQ="$(runs "$(run 9 in_progress)")"
expect "a run still going after the limit fails" 1 "::error::run 9 on $HEAD has not finished after 600s"
check_reran 0 "nothing is re-run past the poll limit"
if [[ "$(grep -c '^sleep 60$' "$TMP_ROOT/log")" == 10 ]]; then ok "it stops after 10 minutes of polls"; else fail "polls: $(grep -c '^sleep 60$' "$TMP_ROOT/log")"; fi
for st in queued waiting pending; do
  STUB_JOBS="$(cijob "$st")"
  expect "a ci-status $st is left to read the reviews when it starts" 0 "ci-status of run 9 has not started"
  check_reran 0 "a $st ci-status is not re-run"
done
STUB_JOBS='{"jobs":[]}'
expect "a run with no ci-status job listed yet is left alone" 0 "has not started"
STUB_RUNS_SEQ="$(runs "$(run 9)")"
expect "a finished run with no ci-status job fails" 1 "::error::run 9 on $HEAD has no ci-status job to re-run."

STUB_RUNS_SEQ="$(runs)" STUB_JOBS="$(cijob completed)"
expect "no run on the head yet is left alone" 0 "No pr-require-checks run on $HEAD yet"
check_reran 0 "nothing is re-run with no run"
STUB_RUNS_SEQ="$(runs "$(run 9)")"

STUB_PR="$(pr closed)"
expect "a closed PR is left alone" 0 "#42 is closed or no longer at $HEAD"
check_reran 0 "a closed PR's ci-status is not re-run"
STUB_PR="$(pr open "${HEAD//0/f}")"
expect "a head the PR moved past is left alone" 0 "no longer at $HEAD"
if grep -q '/runs?' "$TMP_ROOT/log"; then fail "a moved head's runs were read"; else ok "a moved head reads no runs"; fi
STUB_PR="$(pr)"
PR_NUMBER='' expect "a review run with no pull request is left alone" 0 "names no pull request"
if [[ -s "$TMP_ROOT/log" ]]; then fail "a run with no pull request read the API"; else ok "a run with no pull request reads nothing"; fi
PR_NUMBER='1;id' expect "a pull request number that is not a number is left alone" 0 "names no pull request"
HEAD_SHA=main expect "a head that is not a commit SHA fails" 1 "::error::the review run's head 'main' is not a commit SHA."

export STUB_RUNS_FAIL=1
expect "an unreadable run list fails" 1 "::error::could not read the pr-require-checks runs on $HEAD; re-run this run."
unset STUB_RUNS_FAIL
export STUB_RERUN_FAIL=1
expect "a refused re-run fails the job" 1
unset STUB_RERUN_FAIL

test_harness::report
