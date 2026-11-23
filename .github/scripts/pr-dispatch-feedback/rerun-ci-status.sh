#!/usr/bin/env bash
# shellcheck disable=SC2154,SC2249,SC2292,SC2310,SC2311 # the step env sets the inputs; a case with no match and a read failing in a condition fall through on purpose
set -e
# shellcheck source=/dev/null
[[ -z "${RUNNER_TEMP:-}" ]] || ! . "${BASH_SOURCE[0]%/*}/../../actions/log-api-budget/api-budget.bash" 2>/dev/null || api_budget_wrap_gh github-token
if [[ ! $HEAD_SHA =~ ^[0-9a-f]{40}$ ]]; then
  echo "::error::the review run's head '$HEAD_SHA' is not a commit SHA."
  exit 1
fi
approved=.github/workflows/pr-review-approved.yml
listed_human() {
  [[ $REVIEW_RERUNNER_ID =~ ^[1-9][0-9]{0,14}$ ]] &&
    jq -e --argjson id "$REVIEW_RERUNNER_ID" '.actors | any(.id == $id and .kind == "human")' "$TRUSTED_ACTORS" >/dev/null 2>&1
}
if [[ $LANE_PATH == "$approved" ]] && ! listed_human; then
  echo "The approval is by ${REVIEW_RERUNNER_ID:-an unnamed actor}, not a person on the trusted-actor list; it lifts no ci-status hold."
  exit 0
fi
if [[ $LANE_PATH == "$approved" && $REVIEW_ATTEMPT != 1 ]]; then
  echo "Relay attempt ${REVIEW_ATTEMPT:-?} names its re-runner, not the reviewer; nothing to re-run."
  exit 0
fi
if [[ ! $PR_NUMBER =~ ^[1-9][0-9]{0,9}$ ]]; then
  echo "::notice::the upstream run names no pull request; nothing to re-run."
  exit 0
fi
utc='^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$'
if [[ ! $LANE_DONE_AT =~ $utc ]]; then
  echo "::error::the review run's finish time '$LANE_DONE_AT' is not a UTC timestamp."
  exit 1
fi
case $LANE_PATH in
.github/workflows/pr-review-hosted.yml) others='pr-review-security-hosted.yml' ;;
.github/workflows/pr-review-security-hosted.yml) others='pr-review-hosted.yml' ;;
"$approved") others='pr-review-hosted.yml pr-review-security-hosted.yml' ;;
*)
  echo "::error::'$LANE_PATH' is not a review lane or an approval relay."
  exit 1
  ;;
esac
waited=0 etag_path='' etag='' etag_body=''
read_api() {
  local attempt out hdr status left reset after wait cond
  for attempt in 1 2 3; do
    cond=()
    [[ $3 != "$etag_path" || -z $etag ]] || cond=(-H "If-None-Match: $etag")
    if out=$(gh api -i "$3" "${cond[@]}"); then
      printf -v "$1" '%s' "$(sed '1,/^\r\?$/d' <<<"$out")"
      etag_path=$3 etag_body=${!1}
      etag=$(sed '/^\r\?$/q' <<<"$out" | tr -d '\r' | awk -F': *' 'tolower($1) == "etag" { print $2; exit }')
      return 0
    fi
    hdr=$(sed '/^\r\?$/q' <<<"$out")
    status=$(awk 'NR == 1 { print $2 }' <<<"$hdr")
    if [[ $status == 304 && ${#cond[@]} -gt 0 ]]; then
      printf -v "$1" '%s' "$etag_body"
      return 0
    fi
    read -r left reset after < <(tr -d '\r' <<<"$hdr" | awk -F': *' '{ h[tolower($1)] = $2 }
      END { print h["x-ratelimit-remaining"] "-", h["x-ratelimit-reset"] "-", h["retry-after"] "-" }')
    left=${left%-} reset=${reset%-} after=${after%-}
    if [[ $status =~ ^(403|429)$ && $after =~ ^[0-9]{1,5}$ ]]; then
      wait=$((10#$after)) reset=$(($(date +%s) + 10#$after))
    elif [[ $status =~ ^(403|429)$ && $left == 0 && $reset =~ ^[0-9]{1,10}$ ]]; then
      wait=$((reset - $(date +%s)))
      wait=$((wait < 0 ? 1 : wait + 1))
    else
      wait=
    fi
    if [ -n "$wait" ]; then
      if [ $((waited + wait)) -gt "$RATE_WAIT_SECONDS" ]; then
        echo "::error::the token's rate limit blocks reading $2 until $(jq -rn --argjson t "$reset" '$t | strftime("%H:%M:%SZ")'), past this job's ${RATE_WAIT_SECONDS}s cap; ci-status on $HEAD_SHA is not re-run. Re-run this run after the reset."
        exit 1
      fi
      echo "Rate limited reading $2; waiting ${wait}s for the reset."
      sleep "$wait"
      waited=$((waited + wait))
      continue
    fi
    [ "$attempt" -lt 3 ] || { [ -z "${read_soft:-}" ] || return 1; echo "::error::could not read $2; re-run this run." >&2; exit 1; }
    sleep $((attempt * 5))
  done
  echo "::error::could not read $2 after the rate-limit waits; re-run this run." >&2
  exit 1
}
newest() {
  jq -c --arg path ".github/workflows/$1" --arg sha "$HEAD_SHA" --arg repo "$GITHUB_REPOSITORY" '[.workflow_runs[]
    | select(.path == $path and .head_sha == $sha and .event == "pull_request"
      and .head_repository.full_name == $repo)]
    | max_by(.id) // empty'
}
head_runs=''
if read_soft=1 read_api listing "the pull_request runs on $HEAD_SHA" \
  "repos/$GITHUB_REPOSITORY/actions/runs?head_sha=$HEAD_SHA&event=pull_request&per_page=100" &&
  jq -e '(.total_count | numbers) <= (.workflow_runs | arrays | length)' <<<"$listing" >/dev/null 2>&1; then
  head_runs=$listing
else
  echo "The pull_request runs on $HEAD_SHA did not come back whole; each workflow's own runs are read."
fi
file_runs() {
  if [ -n "$head_runs" ]; then
    runs=$head_runs
  else
    read_api runs "the $1 runs on $HEAD_SHA" \
      "repos/$GITHUB_REPOSITORY/actions/workflows/$1/runs?head_sha=$HEAD_SHA&event=pull_request&per_page=100"
  fi
}
done_at=$LANE_DONE_AT
for other in $others; do
  file_runs "$other"
  lane=$(newest "$other" <<<"$runs")
  if [ -n "$lane" ]; then
    if [ "$(jq -r .status <<<"$lane")" != completed ]; then
      echo "$other has not finished on $HEAD_SHA; its completion re-runs ci-status."
      exit 0
    fi
    other_at=$(jq -r '.updated_at // ""' <<<"$lane")
    if [[ $LANE_PATH != "$approved" ]] &&
      jq -e --arg own "$LANE_DONE_AT" --arg own_id "$REVIEW_RUN_ID" 'try (.conclusion != "skipped" and .run_attempt == 1
        and ((.updated_at | fromdateiso8601) as $t | ($own | fromdateiso8601) as $o
          | $t > $o or ($t == $o and .id > ($own_id | tonumber)))) catch false' <<<"$lane" >/dev/null; then
      echo "$other finished on $HEAD_SHA after this lane; its completion re-runs ci-status."
      exit 0
    fi
    if [[ $other_at > $done_at ]]; then
      done_at=$other_at
    fi
  fi
done
file_runs pr-require-checks.yml
run=$(newest pr-require-checks.yml <<<"$runs")
if [ -z "$run" ]; then
  echo "No pr-require-checks run on $HEAD_SHA yet; its ci-status reads the reviews when it runs."
  exit 0
fi
id=$(jq -r .id <<<"$run")
gate_job='([.jobs[] | select(.name == "CI Status")] | if length > 0 then . else null end) // [.jobs[] | select(.name == "ci-status")] | max_by(.id) // empty'
read_api jobs "the jobs of run $id" "repos/$GITHUB_REPOSITORY/actions/runs/$id/jobs?filter=latest&per_page=100"
job=$(jq -c "$gate_job" <<<"$jobs")
if [ "$(jq -r .status <<<"$run")" != completed ]; then
  case $(jq -r '.status // "absent"' <<<"${job:-null}") in
  in_progress | completed) ;;
  *)
    echo "ci-status of run $id has not started; it reads the reviews when it runs."
    exit 0
    ;;
  esac
fi
read_at=$(jq -r 'first(((.steps // [])[] | select(.name == "Require both review lanes on this head") | .started_at | strings),
  (.started_at | strings)) // ""' <<<"${job:-null}")
case $(jq -r --arg s "$read_at" --arg d "$done_at" 'try (($s | fromdateiso8601) as $r | ($d | fromdateiso8601) as $t
  | if $r > $t + 60 then "late" elif .conclusion == "success" and $r >= $t then "passed" else "" end) catch ""' <<<"${job:-null}") in
late)
  echo "ci-status of run $id began reading the reviews at $read_at, after both lanes finished ($done_at); it read them."
  exit 0
  ;;
passed)
  echo "ci-status of run $id passed, reading the reviews from $read_at, after both lanes finished ($done_at); a re-run can only pass again."
  exit 0
  ;;
esac
while [ "$(jq -r .status <<<"$run")" != completed ]; do
  if [ "$waited" -ge "$POLL_LIMIT_SECONDS" ]; then
    echo "::error::run $id on $HEAD_SHA has not finished after ${waited}s; re-run its ci-status job once it does."
    exit 1
  fi
  sleep "$POLL_SECONDS"
  waited=$((waited + POLL_SECONDS)) polled=1
  read_api run "run $id" "repos/$GITHUB_REPOSITORY/actions/runs/$id"
done
if [ -n "${polled:-}" ]; then
  read_api jobs "the jobs of run $id" "repos/$GITHUB_REPOSITORY/actions/runs/$id/jobs?filter=latest&per_page=100"
  job=$(jq -c "$gate_job" <<<"$jobs")
fi
judged_at=$(jq -r 'first((.steps // [])[] | select(.name == "Require both review lanes on this head") | .completed_at | strings) // ""' <<<"${job:-null}")
if jq -e --arg s "$judged_at" --arg d "$done_at" 'try (.conclusion == "success" and ($s | fromdateiso8601) >= ($d | fromdateiso8601)) catch false' <<<"${job:-null}" >/dev/null; then
  echo "ci-status of run $id passed, judging the reviews by $judged_at, after both lanes finished ($done_at); a re-run can only pass again."
  exit 0
fi
job_id=$(jq -r '.id // empty' <<<"${job:-null}")
if [[ ! $job_id =~ ^[1-9][0-9]{0,14}$ ]]; then
  echo "::error::run $id on $HEAD_SHA has no ci-status job to re-run."
  exit 1
fi
read_api pr "#$PR_NUMBER" "repos/$GITHUB_REPOSITORY/pulls/$PR_NUMBER"
if [ "$(jq -r '"\(.state) \(.head.sha)"' <<<"$pr")" != "open $HEAD_SHA" ]; then
  echo "#$PR_NUMBER is closed or no longer at $HEAD_SHA; nothing to re-run."
  exit 0
fi
attempt=$(jq -r '.run_attempt // empty' <<<"$run")
if [[ ! $attempt =~ ^[1-9][0-9]{0,4}$ ]]; then
  echo "::error::run $id on $HEAD_SHA reports no attempt number."
  exit 1
fi
if [[ $attempt == 1 && $LANES_PROCEED != true ]] &&
  jq -e --arg id "$APP_SENDER_ID" 'try ((.user.id | type) != "number" or (.user.type | type) != "string"
    or ($id | test("^[1-9][0-9]*$")) and .user.type == "Bot" and .user.id == ($id | tonumber)) catch true' <<<"$pr" >/dev/null; then
  echo "::notice::the lanes kill switch is on or unread, so ci-status on lanes App #$PR_NUMBER is not re-run; the lost-run reconciler re-runs it once the switch is off."
  exit 0
fi
next=$((attempt + 1))
read_api run "run $id" "repos/$GITHUB_REPOSITORY/actions/runs/$id"
if [ "$(jq -r '"\(.status) \(.run_attempt)"' <<<"$run")" != "completed $attempt" ]; then
  echo "Run $id on $HEAD_SHA moved past attempt $attempt or is running again; that re-run reads the change."
  exit 0
fi
echo "job-id=$job_id" >>"$GITHUB_OUTPUT"
echo "Re-running ci-status (job $job_id) of run $id on $HEAD_SHA as attempt $next."
reconciled() {
  [[ $REVIEW_ATTEMPT == 2 && $REVIEW_RERUNNER_ID == 41898282 && $REVIEW_RUN_ID =~ ^[1-9][0-9]{0,19}$ ]] &&
    node "$RECONCILER_RECORD"
}
case $LANE_PATH in
"$approved")
  vouched=true reason='a listed person approved the head after ci-status read it'
  ;;
*)
  vouched=false reason='the review lanes finished after ci-status read them'
  if [[ $REVIEW_ATTEMPT == 1 ]] || { [[ $REVIEW_ATTEMPT =~ ^[1-9][0-9]{0,4}$ ]] && listed_human; } || reconciled; then vouched=true; fi
  ;;
esac
if [ "$vouched" != true ]; then
  echo "::notice::upstream attempt ${REVIEW_ATTEMPT:-?} was started by ${REVIEW_RERUNNER_ID:-an unnamed actor}, who is not a listed human, and no reconciler record vouches for it; the re-run is not recorded, so pr-verify's gate refuses it."
  exit 0
fi
jq -cn --argjson recorder "$GITHUB_RUN_ID" --argjson run "$id" --argjson attempt "$next" --arg head "$HEAD_SHA" \
  --argjson pr "$PR_NUMBER" --argjson job "$job_id" --arg lane "$LANE_PATH" --arg reason "$reason" \
  '{recorder_run_id: $recorder, run_id: $run, attempt: $attempt, head_sha: $head, pr_number: $pr,
    job_id: $job, lane_path: $lane, reason: $reason}' >"$RECORD_FILE"
echo "record=rerun-ci-status-$id-$next-$HEAD_SHA" >>"$GITHUB_OUTPUT"
