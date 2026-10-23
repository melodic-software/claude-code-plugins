#!/usr/bin/env bash
# Regression tests for review-venue.sh, black-box with a stubbed `gh` on PATH.
# Expected verdicts come from the rule the script header and
# reference/review-venue.md state: healthy only when the newest run with a
# verdict (completed, not skipped or cancelled, and not a skipped-validation
# red) succeeded within the window.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$SCRIPT_DIR/review-venue.sh"
TEST_TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TEST_TMPDIR"' EXIT

# shellcheck source=../../../scripts/test-helpers.sh
source "$SCRIPT_DIR/../../../scripts/test-helpers.sh"

command -v jq >/dev/null 2>&1 || skip_suite "jq not installed"

STUB_DIR="$TEST_TMPDIR/stubs"
mkdir -p "$STUB_DIR"
# The repository's run listing page N comes from $TEST_TMPDIR/page-N.json, a
# lane workflow's runs from $TEST_TMPDIR/wf-<id>.json, a run's jobs from
# jobs-<run-id>.json and a job's annotations from ann-<job-id>.json; a missing
# file fails.
cat >"$STUB_DIR/gh" <<STUB_EOF
#!/usr/bin/env bash
printf '%s\n' "\$*" >>"$TEST_TMPDIR/calls"
[[ "\$1" == api ]] || { echo "gh-stub: unrouted \$*" >&2; exit 1; }
case "\$2" in
  */actions/runs/*/jobs\?*)
    id="\${2#*/actions/runs/}"; id="\${id%%/*}"
    [[ -f "$TEST_TMPDIR/jobs-\$id.json" ]] || exit 1
    cat "$TEST_TMPDIR/jobs-\$id.json"
    ;;
  */check-runs/*/annotations*)
    id="\${2#*/check-runs/}"; id="\${id%%/*}"
    [[ -f "$TEST_TMPDIR/ann-\$id.json" ]] || exit 1
    cat "$TEST_TMPDIR/ann-\$id.json"
    ;;
  */actions/runs\?*)
    page="\${2##*page=}"
    [[ -f "$TEST_TMPDIR/page-\$page.json" ]] || exit 1
    cat "$TEST_TMPDIR/page-\$page.json"
    ;;
  */actions/workflows/*/runs\?*)
    id="\${2#*/actions/workflows/}"; id="\${id%%/*}"
    [[ -f "$TEST_TMPDIR/wf-\$id.json" ]] || exit 1
    # The documented event filter: only runs of that event come back.
    case "\$2" in
      *event=pull_request*) jq -c '.workflow_runs |= map(select(.event == "pull_request"))' "$TEST_TMPDIR/wf-\$id.json" ;;
      *) cat "$TEST_TMPDIR/wf-\$id.json" ;;
    esac
    ;;
  */actions/workflows/*)
    id="\${2##*/}"
    [[ -f "$TEST_TMPDIR/wfmeta-\$id.json" ]] || exit 1
    cat "$TEST_TMPDIR/wfmeta-\$id.json"
    ;;
  *) echo "gh-stub: unrouted \$*" >&2; exit 1 ;;
esac
STUB_EOF
chmod +x "$STUB_DIR/gh"

CODE='melodic-software/ci-workflows/.github/workflows/pr-review.yml@a623e29085a3be885718cf9c0c0eca85bb53dd97'
SEC='melodic-software/ci-workflows/.github/workflows/pr-review-security.yml@a623e29085a3be885718cf9c0c0eca85bb53dd97'

# ago <hours> -> an ISO-8601 UTC time that many hours before now
ago() { jq -nr --argjson h "$1" '(now - $h * 3600) | floor | todate'; }

# lane_run <workflow-id> <path> <reusable> -> one run of the repository listing
lane_run() {
  jq -nc --argjson w "$1" --arg p "$2" --arg r "$3" \
    '{id: 1, workflow_id: $w, path: $p, status: "completed", conclusion: "skipped", referenced_workflows: [{path: $r}]}'
}
other_run() { jq -nc '{id: 2, workflow_id: 999, path: ".github/workflows/ci.yml", status: "completed", conclusion: "success"}'; }

# page <n> <run-json>... -> page-n.json
page() {
  local n="$1"
  shift
  jq -sc '{workflow_runs: .}' <<<"$(printf '%s\n' "$@")" >"$TEST_TMPDIR/page-$n.json"
}

# wf <id> <status:conclusion:hours-ago[:event[:class]]>... -> wf-id.json,
# newest first, event pull_request unless given; the workflow itself reads
# active. A failed run gets one failed lane job whose annotations carry
# `failure-class=<class>` as the reusable workflow's last step writes it
# (ci-workflows .github/workflows/pr-review.yml), class `other` unless given;
# a startup_failure run has no jobs.
NEXT_RUN=1000
wf() {
  local id="$1" spec runs=() rid
  shift
  for spec in "$@"; do
    IFS=: read -r st co h ev cl <<<"$spec"
    rid=$((NEXT_RUN++))
    runs+=("$(jq -nc --arg s "$st" --arg c "$co" --arg t "$(ago "$h")" --arg e "${ev:-pull_request}" --argjson i "$rid" \
      '{id: $i, event: $e, status: $s, conclusion: (if $c == "" then null else $c end), created_at: $t}')")
    case "$co" in
    startup_failure) echo '{"jobs": []}' >"$TEST_TMPDIR/jobs-$rid.json" ;;
    failure | timed_out)
      jq -nc --argjson j "$((rid * 10))" --arg c "$co" \
        '{jobs: [{id: 1, conclusion: "success"}, {id: $j, conclusion: $c}]}' >"$TEST_TMPDIR/jobs-$rid.json"
      jq -nc --arg c "${cl:-other}" '[
        {annotation_level: "failure", message: "Process completed with exit code 1."},
        {annotation_level: "failure", message: "failure-class=\($c): why"}]' >"$TEST_TMPDIR/ann-$((rid * 10)).json"
      ;;
    *) ;;
    esac
  done
  jq -sc '{workflow_runs: .}' <<<"$(printf '%s\n' "${runs[@]}")" >"$TEST_TMPDIR/wf-$id.json"
  wf_state "$id" active
}

# wf_state <id> <state> -> the workflow's state, as GET .../actions/workflows/<id> returns it
wf_state() { jq -nc --arg s "$2" '{state: $s}' >"$TEST_TMPDIR/wfmeta-$1.json"; }

reset() { rm -f "$TEST_TMPDIR"/page-*.json "$TEST_TMPDIR"/wf-*.json "$TEST_TMPDIR"/wfmeta-*.json "$TEST_TMPDIR"/jobs-*.json "$TEST_TMPDIR"/ann-*.json; }

run() {
  : >"$TEST_TMPDIR/calls"
  PATH="$STUB_DIR:$PATH" bash "$SCRIPT" "$@"
}

BOTH_PAGE=("$(other_run)" "$(lane_run 11 .github/workflows/pr-review-hosted.yml "$CODE")" "$(lane_run 22 .github/workflows/pr-review-security-hosted.yml "$SEC")")

reset
page 1 "${BOTH_PAGE[@]}"
wf 11 completed:success:2
wf 22 completed:success:2
out=$(run)
assert_exit "two lanes whose newest run succeeded today exit 0" 0 "$?"
assert_contains "the code lane is covered by CI" "$out" "code-review ci healthy"
assert_contains "the security lane is covered by CI" "$out" "security-review ci healthy"
assert_eq "code-review is reported first" "code-review" "$(head -n1 <<<"$out" | cut -d' ' -f1)"
assert_contains "the line names the caller workflow" "$out" ".github/workflows/pr-review-hosted.yml"

reset
page 1 "${BOTH_PAGE[@]}"
wf 11 completed:skipped:1 completed:cancelled:2 in_progress::0 completed:success:3
wf 22 completed:success:3
out=$(run)
assert_contains "skipped, cancelled and running runs carry no verdict" "$out" "code-review ci healthy"

reset
page 1 "${BOTH_PAGE[@]}"
wf 11 completed:failure:1 completed:success:5
wf 22 completed:success:1
out=$(run)
assert_exit "a failing lane is still a read" 0 "$?"
assert_contains "a lane whose newest verdict failed runs locally" "$out" "code-review local failing"
assert_contains "the failing line names the conclusion" "$out" "concluded failure"
assert_contains "the other lane keeps its own verdict" "$out" "security-review ci healthy"

# #8867: a pull request that edits a review caller workflow ends both lanes red
# by design (failure-class=skipped-validation); that says nothing about the lane.
reset
page 1 "${BOTH_PAGE[@]}"
wf 11 completed:failure:1::skipped-validation completed:success:3
wf 22 completed:failure:1::skipped-validation completed:success:3
out=$(run)
assert_exit "a skipped-validation red is still a read" 0 "$?"
assert_contains "a workflow-editing PR's red leaves the code lane healthy" "$out" "code-review ci healthy"
assert_contains "a workflow-editing PR's red leaves the security lane healthy" "$out" "security-review ci healthy"

reset
page 1 "${BOTH_PAGE[@]}"
wf 11 completed:failure:1::skipped-validation completed:failure:2::auth completed:success:3
wf 22 completed:success:1
out=$(run)
assert_contains "a real failure behind a skipped-validation red still fails" "$out" "code-review local failing"

reset
page 1 "${BOTH_PAGE[@]}"
wf 11 completed:failure:1 completed:failure:2 completed:timed_out:3 completed:success:4
wf 22 completed:failure:1::rate-limit completed:success:2
out=$(run)
assert_contains "a lane whose recent runs all fail reads failing" "$out" "code-review local failing"
assert_contains "a usage-limit stop is not a skipped-validation red" "$out" "security-review local failing"

reset
page 1 "${BOTH_PAGE[@]}"
wf 11 completed:failure:1::skipped-validation completed:failure:2::skipped-validation
wf 22 completed:success:1
out=$(run)
assert_contains "a lane with only skipped-validation reds is stale" "$out" "code-review local stale"

reset
page 1 "${BOTH_PAGE[@]}"
wf 11 completed:failure:1::skipped-validation completed:success:200
wf 22 completed:success:1
out=$(run)
assert_contains "the window applies to the run behind a skipped-validation red" "$out" "code-review local stale"

reset
page 1 "${BOTH_PAGE[@]}"
wf 11 completed:failure:1::skipped-validation completed:success:3
wf 22 completed:success:1
rm -f "$TEST_TMPDIR"/ann-*.json
run >/dev/null 2>&1
assert_exit "unreadable annotations fail closed" 2 "$?"

reset
page 1 "${BOTH_PAGE[@]}"
wf 11 completed:failure:1::skipped-validation completed:success:3
wf 22 completed:success:1
rm -f "$TEST_TMPDIR"/jobs-*.json
run >/dev/null 2>&1
assert_exit "unreadable jobs fail closed" 2 "$?"

reset
page 1 "${BOTH_PAGE[@]}"
wf 11 completed:success:1
wf 22 completed:success:1
run >/dev/null
assert_not_contains "a healthy lane reads no jobs" "$(cat "$TEST_TMPDIR/calls")" "/jobs"

reset
page 1 "${BOTH_PAGE[@]}"
wf 11 completed:timed_out:1
wf 22 completed:startup_failure:1
out=$(run)
assert_contains "a timed-out lane runs locally" "$out" "code-review local failing"
assert_contains "a lane that failed to start runs locally" "$out" "security-review local failing"

reset
page 1 "${BOTH_PAGE[@]}"
wf 11 completed:success:200
wf 22 completed:success:2
out=$(run)
assert_contains "a success older than seven days is stale" "$out" "code-review local stale"
out=$(run --max-age-days 30)
assert_contains "--max-age-days widens the window" "$out" "code-review ci healthy"

reset
page 1 "${BOTH_PAGE[@]}"
wf 11 completed:skipped:1 completed:cancelled:1
wf 22 completed:success:1
out=$(run)
assert_contains "a lane with no run carrying a verdict is stale" "$out" "code-review local stale"

reset
page 1 "${BOTH_PAGE[@]}"
wf 11 completed:success:1
wf_state 11 disabled_manually
wf 22 completed:success:1
wf_state 22 disabled_inactivity
out=$(run)
assert_exit "a disabled lane is still a read" 0 "$?"
assert_contains "a manually disabled lane runs locally despite a recent success" "$out" "code-review local absent"
assert_contains "the line names the workflow state" "$out" "disabled_manually"
assert_contains "a lane disabled for inactivity runs locally" "$out" "security-review local absent"

reset
page 1 "${BOTH_PAGE[@]}"
wf 11 completed:success:1:workflow_dispatch completed:failure:2
wf 22 completed:success:1
out=$(run)
assert_contains "a manual run's success does not mask a failing pull request run" "$out" "code-review local failing"

reset
page 1 "${BOTH_PAGE[@]}"
wf 11 completed:success:1
wf 22 completed:success:1
rm -f "$TEST_TMPDIR/wfmeta-22.json"
run >/dev/null 2>&1
assert_exit "an unreadable workflow state fails closed" 2 "$?"

reset
page 1 "$(other_run)"
out=$(run)
assert_exit "a repository without lanes is still a read" 0 "$?"
assert_contains "no code lane means a local code review" "$out" "code-review local absent"
assert_contains "no security lane means a local security review" "$out" "security-review local absent"
assert_not_contains "no lane's workflow is read when none was found" "$(cat "$TEST_TMPDIR/calls")" "actions/workflows/"

reset
page 1 "$(other_run)" "$(lane_run 11 .github/workflows/pr-review-hosted.yml "$CODE")"
wf 11 completed:success:1
out=$(run)
assert_contains "a code lane alone is covered" "$out" "code-review ci healthy"
assert_contains "the missing security lane runs locally" "$out" "security-review local absent"

reset
page 1 "$(other_run)" "$(lane_run 11 .github/workflows/pr-review.yml 'someone-else/ci-workflows/.github/workflows/pr-review.yml@main')"
out=$(run)
assert_contains "a review workflow from another owner is not a lane" "$out" "code-review local absent"

reset
full=()
for _ in $(seq 100); do full+=("$(other_run)"); done
page 1 "${full[@]}"
page 2 "${BOTH_PAGE[@]}"
wf 11 completed:success:1
wf 22 completed:success:1
out=$(run)
assert_contains "a lane first seen on page 2 is found" "$out" "code-review ci healthy"
assert_contains "page 2 is requested after a full page 1" "$(cat "$TEST_TMPDIR/calls")" "page=2"

reset
page 1 "${BOTH_PAGE[@]}"
wf 11 completed:success:1
wf 22 completed:success:1
run --repo acme/app >/dev/null
assert_contains "--repo reaches gh" "$(cat "$TEST_TMPDIR/calls")" "repos/acme/app/actions/runs"
assert_not_contains "both lanes on page 1 stop the scan" "$(cat "$TEST_TMPDIR/calls")" "page=2"

reset
run >/dev/null 2>&1
assert_exit "an unreadable run listing fails closed" 2 "$?"

reset
page 1 "${BOTH_PAGE[@]}"
wf 11 completed:success:1
run >/dev/null 2>&1
assert_exit "an unreadable lane workflow fails closed" 2 "$?"

reset
echo 'not json' >"$TEST_TMPDIR/page-1.json"
run >/dev/null 2>&1
assert_exit "an unparsable run listing fails closed" 2 "$?"

# pr-review-cli.yml serves either lane; it counts for security-review only from
# a caller whose path names security, so the security lane never takes a
# code-lane caller of it.
CLI='melodic-software/ci-workflows/.github/workflows/pr-review-cli.yml@83b739f625b501ad40c65dee7168d836883195e1'
reset
page 1 "$(other_run)" "$(lane_run 11 .github/workflows/pr-review-hosted.yml "$CODE")" \
  "$(lane_run 33 .github/workflows/pr-review-cli-code.yml "$CLI")" \
  "$(lane_run 22 .github/workflows/pr-review-security-hosted.yml "$CLI")"
wf 11 completed:success:2
wf 22 completed:success:2
out=$(run)
assert_exit "a security caller of pr-review-cli exits 0" 0 "$?"
assert_contains "a security caller of pr-review-cli covers the security lane" "$out" \
  "security-review ci healthy"
assert_contains "the security line names the pr-review-cli caller" "$out" \
  ".github/workflows/pr-review-security-hosted.yml"

# Both lanes on pr-review-cli: code-review takes the caller whose path does not
# name security, even when the security caller's run is listed first.
reset
page 1 "$(other_run)" "$(lane_run 22 .github/workflows/pr-review-security-hosted.yml "$CLI")" \
  "$(lane_run 11 .github/workflows/pr-review-hosted.yml "$CLI")"
wf 11 completed:success:2
wf 22 completed:failure:2
out=$(run)
assert_exit "two pr-review-cli callers exit 0" 0 "$?"
assert_contains "a code caller of pr-review-cli covers the code lane" "$out" \
  "code-review ci healthy"
assert_contains "the code line names its own caller" "$out" \
  "(.github/workflows/pr-review-hosted.yml)"
assert_contains "the security lane keeps its own caller's verdict" "$out" \
  "security-review local failing"

# pr-review-cli writes the class after the lane id: still a skipped-validation red.
reset
page 1 "${BOTH_PAGE[@]}"
wf 11 completed:success:2
wf 22 completed:failure:1::skipped-validation completed:success:3
jq '.[1].message |= "claude-security-review: " + .' "$TEST_TMPDIR/ann-$(((NEXT_RUN - 2) * 10)).json" >"$TEST_TMPDIR/ann.tmp" &&
  mv "$TEST_TMPDIR/ann.tmp" "$TEST_TMPDIR/ann-$(((NEXT_RUN - 2) * 10)).json"
out=$(run)
assert_contains "a lane-prefixed skipped-validation red reaches no verdict" "$out" \
  "security-review ci healthy"

run --repo 'acme app' >/dev/null 2>&1
assert_exit "a malformed --repo exits 1" 1 "$?"
run --max-age-days 0 >/dev/null 2>&1
assert_exit "a zero-day window exits 1" 1 "$?"
run --pr 7 >/dev/null 2>&1
assert_exit "an unknown flag exits 1" 1 "$?"

[[ $FAILED -eq 0 ]] || exit 1
