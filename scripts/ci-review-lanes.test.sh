#!/usr/bin/env bash
# Runs the `Require both review lanes on this head` step body of
# .github/workflows/pr-require-checks.yml's ci-status under the shell Actions
# gives a step with no `shell:` (bash -e), against stub `gh` and `sleep`.
#
# On a ready pull request, ci-status passes only when the newest pull_request
# run of each review caller on the head has a successful status job whose
# `Apply the hold` step ran. Pending, failed, skipped or missing reviews fail
# with the cause named; a lane the kill switch stopped passes; Dependabot, the
# release App and the standards-sync App are exempt by numeric author id. It
# fails closed when it cannot read.
# test-scope: .github/workflows/pr-require-checks.yml
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORKFLOW="$ROOT/.github/workflows/pr-require-checks.yml"

# shellcheck source=lib/test-harness.sh
. "$ROOT/scripts/lib/test-harness.sh"

TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT

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
if [[ "$step" == *"continue-on-error"* ]]; then
  fail "step must not continue on error: its exit code is the gate"
else
  ok "step fails the job on its exit code"
fi
order="$(grep -nE "^  ci-status:$|^      - name: ($NAME|Aggregate lane results)$" "$WORKFLOW" | cut -d: -f1 | paste -sd' ')"
read -r job_line lanes_line agg_line <<<"$order"
if [[ -n "${agg_line:-}" && "$job_line" -lt "$lanes_line" && "$lanes_line" -lt "$agg_line" ]]; then
  ok "step sits in ci-status before the aggregate, so ci-lanes is written when it fails"
else
  fail "step is not inside ci-status before the aggregate (lines: $order)"
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
    grep -qE '^    uses: melodic-software/ci-workflows/\.github/workflows/pr-review-cli\.yml@9aca743c4ed9aaf7870288a36586c3994e9321e4 # v0\.64\.1$' "$caller"; then
    ok "$file calls pr-review-cli v0.64.1 as job ${job%:} with publish: comments and hold-label: needs-human"
  else
    fail "$file lost its job id, publish: comments, hold-label or v0.64.1 pin"
  fi
  paths="$(awk '/^      hold-paths: \|$/ { on = 1; next } on && /^        / { sub(/^ +/, ""); print; next } on { exit }' "$caller")"
  if [[ "$paths" == $'.github/standards/trusted-actors/**\n.github/actions/check-trusted-trigger/**\n**/CODEOWNERS\n**/.gitmodules' ]]; then
    ok "$file holds on the four trust-gate paths"
  else
    fail "$file hold-paths are '$paths'"
  fi
done

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
# run <id> <file> [status] [sha] [event]
run() { jq -cn --argjson id "$1" --arg f "$2" --arg st "${3:-completed}" --arg sha "${4:-$HEAD}" --arg ev "${5:-pull_request}" \
  '{id: $id, path: (".github/workflows/" + $f), status: $st, head_sha: $sha, event: $ev, html_url: ("https://github.com/o/r/actions/runs/\($id)")}'; }
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
  out="$(PATH="$TMP_ROOT/bin:$PATH" STUB_LOG="$TMP_ROOT/log" GITHUB_REPOSITORY=o/r HEAD_SHA="${HEAD_SHA-$HEAD}" \
    AUTHOR_ID="${AUTHOR_ID-153232337}" bash -e "$TMP_ROOT/body.sh" 2>&1)" && rc=0 || rc=$?
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
JOBS_10="$(jobs "$(kill_job success skipped)" "$(status "$CODE_CHECK" completed skipped skipped)")"
expect "a skipped review (fork or unlisted bot) fails" 1 "::error::'$CODE_CHECK' did not run on $HEAD (https://github.com/o/r/actions/runs/10; kill-switch job: success)"
JOBS_10="$(jobs "$(kill_job success success)")"
expect "a lane the kill switch stopped passes" 0 "::notice::a kill switch stopped '$CODE_CHECK' on $HEAD" "::error::"
JOBS_10="$(jobs "$(kill_job success success)" "$(status "$CODE_CHECK" completed skipped skipped)")"
expect "a kill-switch stop with the review listed as skipped passes" 0 "a kill switch stopped" "::error::"
JOBS_10="$(jobs "$(kill_job failure skipped)")"
expect "a failed kill-switch job fails" 1 "kill-switch job: failure"
JOBS_10="$(jobs "$(kill_job success skipped)")"
expect "a kill-switch job that let the review run, with no review, fails" 1 "did not run on $HEAD"

JOBS_10="$PASS_CODE"
RUNS_SEC="$(runs)"
expect "the security lane is required too" 1 "::error::'$SEC_CHECK' is missing" "'$CODE_CHECK' is missing"
RUNS_CODE="$(runs)"
expect "both missing lanes are named" 1 "'$CODE_CHECK' is missing"
RUNS_CODE="$(runs "$(run 10 $CODE)")" RUNS_SEC="$(runs "$(run 20 $SEC)")"

for id in 49699333 337859524 300666570; do
  RUNS_CODE="$(runs)"
  AUTHOR_ID=$id expect "author $id is exempt without a read" 0 "is one no review lane reviews"
  if [[ -s "$TMP_ROOT/log" ]]; then fail "an exempt author's run read the API"; else ok "an exempt author's run reads nothing"; fi
done
AUTHOR_ID=49699333999 expect "an id that only contains an exempt id is not exempt" 1 "is missing"
RUNS_CODE="$(runs "$(run 10 $CODE)")"

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
