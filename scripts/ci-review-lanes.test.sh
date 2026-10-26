#!/usr/bin/env bash
# Runs the `Require both review lanes on this head` step body of
# .github/workflows/pr-require-checks.yml's ci-status under the shell Actions
# gives a step with no `shell:` (bash -e), against stub `gh` and `sleep`.
#
# On a ready pull request, ci-status passes only when the newest pull_request
# run of each review caller on the head has a successful status job whose
# `Apply the hold` step ran. Pending, failed, skipped or missing reviews fail
# with the cause named, a lane the kill switch stopped among them; Dependabot, the
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
    grep -qE '^    uses: melodic-software/ci-workflows/\.github/workflows/pr-review-cli\.yml@ba7af78d291f10bd75651857a0db2357c23df0fe # v0\.65\.13$' "$caller"; then
    ok "$file calls pr-review-cli v0.65.13 as job ${job%:} with publish: comments and hold-label: needs-human"
  else
    fail "$file lost its job id, publish: comments, hold-label or v0.65.13 pin"
  fi
  # pr-review-cli's check-key-credit job requests actions: read; a caller that
  # does not grant it fails at startup.
  if awk -v job="  $job" '$0 == job { on = 1; next } on && /^  [^ ]/ { exit } on && /^      actions: read( |$)/ { found = 1 } END { exit !found }' "$caller"; then
    ok "$file grants actions: read to job ${job%:}"
  else
    fail "$file does not grant actions: read to job ${job%:}"
  fi
  paths="$(awk '/^      hold-paths: \|$/ { on = 1; next } on && /^        / { sub(/^ +/, ""); print; next } on { exit }' "$caller")"
  if [[ "$paths" == $'.github/standards/trusted-actors/**\n.github/actions/check-trusted-trigger/**\n**/CODEOWNERS\n**/.gitmodules' ]]; then
    ok "$file sends the four trust-gate paths to extra security scrutiny"
  else
    fail "$file hold-paths are '$paths'"
  fi
done

# An exempt author's pull request, which no review lane reads, still fails on
# the four trust-gate paths in bash form: `**/X` is X or */X, a trailing `**`
# is `*`.
want_patterns="$(printf '%s\n' '.github/standards/trusted-actors/*' '.github/actions/check-trusted-trigger/*' CODEOWNERS '*/CODEOWNERS' .gitmodules '*/.gitmodules' | sort)"
got_patterns="$(sed -nE 's/^ *hold_patterns=\((.*)\)$/\1/p' "$TMP_ROOT/body.sh" | tr ' ' '\n' | tr -d "'" | sort)"
if [[ -n "$got_patterns" && "$got_patterns" == "$want_patterns" ]]; then
  ok "the exempt-author hold patterns are the four trust-gate paths"
else
  fail "exempt-author hold patterns '$got_patterns' are not the four trust-gate paths '$want_patterns'"
fi

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
*/pulls/*) jq -cn --argjson n "${STUB_CHANGED:-0}" '{changed_files: $n}' ;;
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
# run <id> <file> [status] [sha] [event] [head repository]
run() { jq -cn --argjson id "$1" --arg f "$2" --arg st "${3:-completed}" --arg sha "${4:-$HEAD}" --arg ev "${5:-pull_request}" --arg hr "${6:-o/r}" \
  '{id: $id, path: (".github/workflows/" + $f), status: $st, head_sha: $sha, event: $ev, head_repository: {full_name: $hr},
    html_url: ("https://github.com/o/r/actions/runs/\($id)")}'; }
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
  rm -f "$TMP_ROOT/pr-files.json"
  [[ -z "${SHARED_FILES:-}" ]] || printf '%s\n' "$SHARED_FILES" >"$TMP_ROOT/pr-files.json"
  out="$(PATH="$TMP_ROOT/bin:$PATH" STUB_LOG="$TMP_ROOT/log" GITHUB_REPOSITORY=o/r HEAD_SHA="${HEAD_SHA-$HEAD}" \
    AUTHOR_ID="${AUTHOR_ID-153232337}" HEAD_REPO="${HEAD_REPO-o/r}" RUNNER_TEMP="$TMP_ROOT" bash -e "$TMP_ROOT/body.sh" 2>&1)" && rc=0 || rc=$?
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
if grep -q '/annotations' "$TMP_ROOT/log"; then fail "a listed hold step still read the annotations"; else ok "a listed hold step decides without reading annotations"; fi

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
expect "a listed skipped hold step stays uncounted despite a notice" 1 "but its 'Apply the hold' step did not run"
if grep -q '/annotations' "$TMP_ROOT/log"; then fail "a listed hold step read the annotations"; else ok "a listed hold step reads no annotations"; fi


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
  "::error::'$CODE_CHECK' did not run on $HEAD (https://github.com/o/r/actions/runs/10): a kill switch was on when it started. Once it is off, re-run all jobs of https://github.com/o/r/actions/runs/10; ci-status re-runs when it finishes." "::notice::"
JOBS_10="$(jobs "$(kill_job success success)" "$(status "$CODE_CHECK" completed skipped skipped)")"
expect "a kill-switch stop with the review listed as skipped fails" 1 "a kill switch was on when it started" "::notice::"
JOBS_10="$(jobs "$(kill_job success success)")" JOBS_20="$(jobs "$(kill_job success success)")"
expect "both lanes stopped by the kill switch fail, each named" 1 "'$SEC_CHECK' did not run on $HEAD (https://github.com/o/r/actions/runs/20): a kill switch was on when it started"
JOBS_20="$PASS_SEC"
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
# Every hold path the callers list holds an exempt author's PR, nested and renamed ones too.
for changed in .github/standards/trusted-actors/trusted-actors.json .github/actions/check-trusted-trigger/lib/x.mjs CODEOWNERS .github/CODEOWNERS \
  .gitmodules vendor/sub/.gitmodules 'docs/new.md<.github/CODEOWNERS'; do
  STUB_FILES="$(files README.md "$changed")"
  AUTHOR_ID=300666570 expect "an exempt author changing $changed fails" 1 "::error::#77 is by an author no review lane reviews and changes trust-gate paths:"
done
for changed in .github/standards/other.json CODEOWNERS.md docs/gitmodules.md .github/actions/check-trusted-trigger-x/a.mjs; do
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
