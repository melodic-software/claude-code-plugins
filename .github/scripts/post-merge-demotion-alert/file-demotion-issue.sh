#!/usr/bin/env bash
# shellcheck disable=SC1091,SC2154,SC2310,SC2311 # the step env sets the inputs and main's checkout holds the sourced files; a function called in a condition runs without set -e on purpose
set -e
[[ -z "${RUNNER_TEMP:-}" ]] || ! . "${BASH_SOURCE[0]%/*}/../../../.github/actions/log-api-budget/api-budget.bash" 2>/dev/null || api_budget_wrap_gh github-token
. .base/.github/scripts/post-merge-demotion-alert/handoff.bash
handoff_failed=''
if [[ "$RETRY_OUTCOME" == failure ]]; then
  handoff_failed=1
fi
trap '[[ -z "$handoff_failed" ]] || exit 1' EXIT
case "$RUN_WORKFLOW:$RUN_EVENT" in
  "PR Require Checks:schedule") signal=schedule ;;
  "PR Require Checks:workflow_dispatch") signal=dispatch ;;
  "Post Merge Detect Silent Revert:push") signal=canary ;;
  *)
    echo "$RUN_WORKFLOW on $RUN_EVENT is not a post-merge signal"
    exit 0
    ;;
esac
quiet=''
case "$RUN_CONCLUSION" in
  failure | timed_out | startup_failure | cancelled) passed='' ;;
  action_required)
    if [[ "$signal" == canary ]]; then
      quiet=1
    elif [[ "$EVENT_NAME" != workflow_dispatch ]]; then
      echo "$RUN_WORKFLOW concluded $RUN_CONCLUSION: nothing to file"
      exit 0
    fi
    passed=''
    ;;
  success)
    if [[ "$RUN_ATTEMPT" =~ ^[0-9]+$ && "$RUN_ATTEMPT" -ge 2 ]]; then
      passed=1
    elif [[ "$signal" == canary ]]; then
      passed='' quiet=1
    else
      echo "$RUN_WORKFLOW passed on attempt $RUN_ATTEMPT: nothing to file"
      exit 0
    fi
    ;;
  *)
    if [[ "$signal" != canary ]]; then
      echo "$RUN_WORKFLOW concluded $RUN_CONCLUSION: nothing to file"
      exit 0
    fi
    passed='' quiet=1
    ;;
esac
if [[ "$RUN_BRANCH" != main || "$RUN_REPO" != "$GITHUB_REPOSITORY" ]]; then
  echo "the run is not on this repository's main branch"
  exit 0
fi
if [[ ! "$RUN_SHA" =~ ^[0-9a-f]{40}$ ]]; then
  echo "::error::head SHA '$RUN_SHA' is not a full commit SHA"
  exit 1
fi
if [[ ! "$RUN_ATTEMPT" =~ ^[1-9][0-9]*$ ]]; then
  echo "::error::run attempt '$RUN_ATTEMPT' is not a positive integer"
  exit 1
fi
if [[ "$RUN_CONCLUSION" == cancelled && "$signal" != canary ]] &&
  jobs="$(gh api "repos/$GITHUB_REPOSITORY/actions/runs/$RUN_ID/attempts/$RUN_ATTEMPT/jobs?per_page=1" \
    --jq '.total_count // (.jobs | length)')" && [[ "$jobs" == 0 ]]; then
  echo "$RUN_WORKFLOW was cancelled before any job started (a newer dispatch replaced it): nothing to file"
  exit 0
fi
newly=''
if [[ -z "$passed" && "$signal" != canary ]]; then
  . .base/.github/scripts/post-merge-demotion-alert/newer-green.bash
  newer_green() {
    newer_green_of "$GITHUB_REPOSITORY" "$RUN_WORKFLOW_ID" "$RUN_ID" "$RUN_CREATED" "$RUN_SHA"
  }
  main_recovered() {
    local newer_id newer_sha
    IFS=$'\t' read -r newer_id newer_sha <<<"$1"
    echo "::notice::$RUN_URL is red at attempt $RUN_ATTEMPT, but main already recovered: run $newer_id at ${newer_sha:0:12} passed on main after it, so nothing filed"
    echo 'recovered=true' >>"$GITHUB_OUTPUT"
    exit 0
  }
  if [[ "$RUN_ATTEMPT" -eq 1 && ("$RUN_TRIGGERING_ACTOR" != 'github-actions[bot]' || "$EVENT_NAME" == workflow_dispatch) ]]; then
    polls=20
    if [[ "$RUN_TRIGGERING_ACTOR" == 'github-actions[bot]' ]]; then
      polls="$(sed -n '/^red-main:/,/^[^[:space:]#]/ s/^  confirm-wait-minutes: \([0-9]*\).*/\1/p' \
        .base/docs/conventions/pr-pipeline.yaml 2>/dev/null | head -n 1)" || polls=''
      [[ "$polls" =~ ^[1-9][0-9]*$ ]] || polls=40
      ((polls <= 60)) || polls=60
    elif ! gh api -X POST "repos/$GITHUB_REPOSITORY/actions/runs/$RUN_ID/rerun-failed-jobs" >/dev/null; then
      echo "::warning::could not re-run $RUN_URL; waiting for any re-run already started"
    fi
    for _ in $(seq "$polls"); do
      sleep "${POLL_SECONDS:-60}"
      latest="$(gh api "repos/$GITHUB_REPOSITORY/actions/runs/$RUN_ID" \
        --jq '[.run_attempt, .status, (.conclusion // "")] | @tsv')" || continue
      IFS=$'\t' read -r attempt status conclusion <<<"$latest"
      if [[ "$attempt" =~ ^[0-9]+$ && "$attempt" -ge 2 && "$status" == completed ]]; then
        if [[ "$conclusion" == success ]]; then
          echo "attempt $attempt, the re-run of the failed jobs, passed: nothing to file"
          exit 0
        fi
        RUN_ATTEMPT="$attempt"
        break
      fi
      if [[ "$EVENT_NAME" == workflow_dispatch ]] && newer="$(newer_green)" && [[ -n "$newer" ]]; then
        main_recovered "$newer"
      fi
    done
    if [[ "$RUN_ATTEMPT" -eq 1 ]]; then
      echo "::warning::the re-run of $RUN_URL did not finish within $polls minutes: judging attempt 1"
    fi
  fi
  if [[ "$EVENT_NAME" == workflow_dispatch ]] && newer="$(newer_green)" && [[ -n "$newer" ]]; then
    main_recovered "$newer"
  fi
  failing_checks() {
    node .base/.github/scripts/post-merge-demotion-alert/failing-checks.mjs "$@"
  }
  now="$(mktemp)"
  kept="$(mktemp)"
  before="$(mktemp)"
  trap 'rm -f -- "$now" "$now.new" "$kept" "$before"; [[ -z "$handoff_failed" ]] || exit 1' EXIT
  failing_checks "$RUN_ID" "$RUN_ATTEMPT" >"$now"
  if [[ ! -s "$now" ]]; then
    echo "::warning::$RUN_URL failed only on checks no merge can cause (the all-branches gitleaks scan): not a demotion"
    exit 0
  fi
  baseline="$(gh api "repos/$GITHUB_REPOSITORY/actions/workflows/$RUN_WORKFLOW_ID/runs?event=$RUN_EVENT&branch=main&status=completed&created=%3C$RUN_CREATED&per_page=20" \
    --jq '[.workflow_runs[] | select(.head_branch == "main" and .head_sha != env.RUN_SHA and .created_at < env.RUN_CREATED)]
      | max_by(.created_at) // empty | [.id, .run_attempt, .conclusion] | @tsv')"
  if [[ -n "$baseline" ]]; then
    IFS=$'\t' read -r base_id base_attempt base_conclusion <<<"$baseline"
    if [[ "$base_conclusion" != success ]]; then
      failing_checks "$base_id" "$base_attempt" --baseline >"$before"
    fi
    grep -xFf "$before" "$now" >"$kept" || true
    grep -vxFf "$before" "$now" >"$now.new" || true
    mv "$now.new" "$now"
  fi
  judged=0
  judgment="$(python3 .base/plugins/source-control/skills/babysit-prs/scripts/babysit_postmerge.py \
    --repo "$GITHUB_REPOSITORY" --judge-run "$RUN_ID" --attempt "$RUN_ATTEMPT" \
    --checks-file "$now" --baseline-checks-file "$kept" --file-quarantine)" || judged=$?
  printf '%s\n' "$judgment"
  quarantined="$(jq -r '.quarantine.issues[]? | select(type == "number")' <<<"$judgment" 2>/dev/null)" || quarantined=''
  for q in $quarantined; do
    if ! send_to_intake "$q"; then
      echo "::error::quarantine issue #$q was not sent to intake triage: the next alert run retries it"
      mark_undelivered "$q" "issue=$q" || true
      handoff_failed=1
    fi
  done
  if ((judged >= 2 && judged <= 4)); then
    error="$(jq -r '.error // empty' <<<"$judgment" 2>/dev/null)" || error=''
    [[ -n "$error" ]] || error='no error in its output'
    error="${error//'%'/%25}"
    error="${error//$'\r'/%0D}"
    echo "::warning::the suite judge exited $judged, so every newly failing check demotes: ${error//$'\n'/%0A}"
  fi
  if [[ "$judged" -eq 0 && -s "$now" ]]; then
    echo "::notice::$RUN_URL failed only in suites outside the merges' affected set or quarantined: not a demotion"
    echo 'excused=true' >>"$GITHUB_OUTPUT"
    exit 0
  fi
  newly_red="$(cat "$now")"
  if [[ "$judged" -eq 1 ]] &&
    demoted="$(jq -r '.demoting[]?' <<<"$judgment" 2>/dev/null)" && [[ -n "$demoted" ]]; then
    printf '%s\n' "$demoted" >"$now"
  fi
  if [[ ! -s "$now" ]]; then
    echo "::warning::$RUN_URL failed only on checks already failing before ${RUN_SHA:0:12} (run $base_id): not a demotion"
    exit 0
  fi
  if [[ -z "$newly_red" ]]; then
    echo "::warning::$RUN_URL failed on checks already failing before ${RUN_SHA:0:12}, whose suites' quarantine expired: a demotion"
  fi
  newly=1
fi
sighting="$RUN_URL/attempts/$RUN_ATTEMPT"
again='The post-merge check found this failure again: '
repo_url="${GITHUB_SERVER_URL:-https://github.com}/$GITHUB_REPOSITORY"

range=()
no_range=''
unknown='so the merges this failure covers are unknown; only the head commit is listed.'
declare -A parent=() entry=()
if [[ "$signal" != canary ]]; then
  if ! base="$(gh api "repos/$GITHUB_REPOSITORY/actions/workflows/$RUN_WORKFLOW_ID/runs?branch=main&status=success&created=%3C$RUN_CREATED&per_page=100" \
    --jq '[.workflow_runs[] | select(.head_branch == "main" and (.event | IN("schedule", "workflow_dispatch"))
      and .created_at < env.RUN_CREATED)]
      | max_by(.created_at) // empty | .head_sha')"; then
    base=''
    echo "::warning::could not read main's green full runs before $RUN_URL: its range is unknown"
    no_range="Main's earlier full runs could not be read, $unknown"
  elif [[ ! "$base" =~ ^[0-9a-f]{40}$ ]]; then
    no_range="No green full run on main came before this one, $unknown"
  elif [[ "$base" == "$RUN_SHA" ]]; then
    no_range="Main's last green full run is at this same commit, so no merge is implicated; only the head commit is listed."
  else
    commits='' page=1 pages=1
    while [[ "$page" -le "$pages" ]]; do
      if ! got="$(gh api "repos/$GITHUB_REPOSITORY/compare/$base...$RUN_SHA?per_page=100&page=$page" \
        --jq '(.total_commits | tostring), (.commits[] | [.sha, (.parents[0].sha // "none"), (.author.login // "unknown"),
          (.commit.message | split("\n")[0] | gsub("\r"; "") | gsub("\t"; " "))] | join("\t"))')" ||
        [[ ! "${got%%$'\n'*}" =~ ^[0-9]+$ ]]; then
        echo "::warning::could not list page $page of the commits from $base to $RUN_SHA: the range is unknown"
        no_range="The commits since main's last green full run at \`$base\` could not be listed, $unknown"
        break
      fi
      if [[ "$page" -eq 1 ]]; then
        total="${got%%$'\n'*}"
        pages=$(((total + 99) / 100))
        if [[ "$total" -gt 300 ]]; then
          no_range="The $total commits since main's last green full run at \`$base\` are more than the 300 this check lists, $unknown"
          break
        fi
      fi
      commits="$commits$(sed 1d <<<"$got")"$'\n'
      page=$((page + 1))
    done
    if [[ -z "$no_range" ]]; then
      while IFS=$'\t' read -r c p a s; do
        if [[ -n "$c" ]]; then
          parent[$c]="$p"
          entry[$c]="$a"$'\t'"$s"
        fi
      done <<<"$commits"
      at="$RUN_SHA"
      while [[ -n "$at" && "$at" != "$base" && -n "${entry[$at]+x}" ]]; do
        range=("$at" "${range[@]}")
        at="${parent[$at]}"
      done
      if [[ "$at" != "$base" ]]; then
        range=()
        no_range="Main's first-parent history from this commit does not reach its last green full run at \`$base\`, $unknown"
      fi
    fi
  fi
fi

lane=1
reverted=()
classify() {
  declare -A numbers=()
  missing=''
  if [[ "${#reverted[@]}" -gt 0 ]]; then
    for n in "${reverted[@]}"; do
      numbers[$n]=1
    done
  elif [[ "${#range[@]}" -gt 0 && "${#range[@]}" -le 100 ]]; then
    for c in "${range[@]}"; do
      s="${entry[$c]#*$'\t'}"
      if [[ "$s" =~ \(#([0-9]+)\)$ ]]; then
        numbers[${BASH_REMATCH[1]}]=1
      else
        missing=1
      fi
    done
  else
    missing=1
  fi
  if [[ "$configured_identity" =~ ^[A-Za-z0-9-]+(\[bot\])?$ && -z "$missing" ]]; then
    fields=''
    for n in "${!numbers[@]}"; do
      fields="$fields p$n: pullRequest(number: $n) { timelineItems(itemTypes: [ADDED_TO_MERGE_QUEUE_EVENT], last: 1) {
      nodes { ... on AddedToMergeQueueEvent { actor { __typename login } enqueuer { __typename login } } } } }"
    done
    query="query(\$owner: String!, \$name: String!) { rateLimit { cost remaining }
    repository(owner: \$owner, name: \$name) { $fields } }"
    verdicts="$(IDENTITY="$configured_identity" gh api graphql -f query="$query" \
      -f owner="${GITHUB_REPOSITORY%%/*}" -f name="${GITHUB_REPOSITORY#*/}" \
      --jq 'def key: ((.login // "") | ascii_downcase)
        + (if .__typename == "Bot" and ((.login // "") | endswith("[bot]") | not) then "[bot]" else "" end);
      "cost \(.data.rateLimit.cost) remaining \(.data.rateLimit.remaining)",
      (.data.repository | to_entries[] | .value.timelineItems.nodes[-1]? // null
        | if . == null then "unproven"
          elif any(.actor, .enqueuer; key == (env.IDENTITY | ascii_downcase)) then "lane"
          else "other" end)')" || verdicts=''
    echo "merge-queue lookup for ${#numbers[@]} pull requests: ${verdicts%%$'\n'*}"
    others="$(grep -cx other <<<"$verdicts" || true)"
    if [[ "$verdicts" == cost* && "$others" -eq "${#numbers[@]}" ]]; then
      lane=''
    fi
  fi
}

marker="<!-- babysit-merge-demotion sha=$RUN_SHA signal=$signal -->"
failure_marker="<!-- post-merge-failure sha=$RUN_SHA signal=$signal -->"
load_records() {
  if [[ -n "${records_read:-}" ]]; then
    return 0
  fi
  records_read=1
  configured_identity="$(gh api -H 'Accept: application/vnd.github.raw' \
    "repos/$GITHUB_REPOSITORY/contents/docs/conventions/pr-pipeline.yaml?ref=main" |
    sed -n '/^merge:/,/^[^[:space:]#]/ s/^  agent-identity: \([^[:space:]]*\)[[:space:]]*$/\1/p')" || configured_identity=''
  lane_filer="$configured_identity"
  filers=(github-actions%5Bbot%5D)
  if [[ "$lane_filer" =~ ^[A-Za-z0-9]+(-[A-Za-z0-9]+)*\[bot\]$ ]]; then
    filers+=("${lane_filer%\[bot\]}%5Bbot%5D")
  else
    lane_filer=''
  fi
  read_records() {
    gh api --paginate \
      "repos/$GITHUB_REPOSITORY/issues?state=all&creator=$1&per_page=100" \
      --jq '.[] | select(.pull_request == null) | [.number, .state, (.state_reason // "none"), (.body // "")]
      | [.[0], .[1], .[2], (.[3] | sub("^[\\t\\n\\f\\r ]+"; "") | split("\n")[0] | sub("[\\t\\n\\f\\r ]+$"; "")),
         ([.[3] | split("\n")[] | select(startswith("- Failing run: "))][0] // ""
          | ltrimstr("- Failing run: ") | sub("[\\t\\n\\f\\r ]+$"; "")),
         ([.[3] | split("\n")[] | capture("^- Revert commit: \u0060(?<c>[0-9a-f]{40})\u0060").c] | join(" ") | if . == "" then "none" else . end),
         (if any(.[3] | split("\n")[]; startswith("<!-- lift-content v1 ")) then "block" else "none" end)]
      | @tsv'
  }
  own_records="$(read_records "${filers[0]}")"
  records="$own_records"$'\n'
  if [[ -n "${filers[1]:-}" ]]; then
    if lane_records="$(read_records "${filers[1]}")"; then
      records+="$lane_records"
    else
      echo "::warning::could not read $lane_filer's records; matching this workflow's own records only"
    fi
  fi
}

subject_pr() {
  local s
  if ! s="$(git -C .base log -1 --format=%s "$1" -- 2>/dev/null)"; then
    s="$(gh api "repos/$GITHUB_REPOSITORY/commits/$1" --jq '.commit.message | split("\n")[0]')" || {
      echo '?'
      return 0
    }
  fi
  if [[ "$s" =~ \(#([1-9][0-9]*)\)$ ]]; then
    echo "${BASH_REMATCH[1]}"
  fi
}
pushed=() in_checkout='' whole_push=''
push_range() {
  local prev
  if ((${#pushed[@]})); then
    return 0
  fi
  prev="$(gh api "repos/$GITHUB_REPOSITORY/actions/workflows/$RUN_WORKFLOW_ID/runs?event=push&branch=main&created=%3C$RUN_CREATED&per_page=20" \
    --jq '[.workflow_runs[] | select(.head_branch == "main" and .head_sha != env.RUN_SHA and .created_at < env.RUN_CREATED)]
      | max_by(.created_at) // empty | .head_sha')" || prev=''
  if ! git -C .base cat-file -e "$RUN_SHA^{commit}" 2>/dev/null; then
    echo "::warning::${RUN_SHA:0:12} is not in the checkout: reading its own message only"
  elif [[ "$prev" =~ ^[0-9a-f]{40}$ ]] && git -C .base merge-base --is-ancestor "$prev" "$RUN_SHA" 2>/dev/null; then
    mapfile -t pushed < <(git -C .base rev-list --first-parent --max-count=21 "$prev..$RUN_SHA" 2>/dev/null)
    if ((${#pushed[@]} > 20)); then
      echo "::warning::more than 20 commits since the previous canary push run at ${prev:0:12}: reading the newest 20"
      pushed=("${pushed[@]:0:20}")
    elif ((${#pushed[@]})); then
      whole_push=1
    fi
  else
    echo "::warning::the previous canary push run's head could not be read or is not on ${RUN_SHA:0:12}'s history: reading the newest 20 commits"
    mapfile -t pushed < <(git -C .base rev-list --first-parent --max-count=20 "$RUN_SHA" 2>/dev/null)
  fi
  if ((${#pushed[@]} == 0)); then
    pushed=("$RUN_SHA")
  else
    in_checkout=1
  fi
}
lift_block_of() {
  local tool=.base/plugins/source-control/skills/babysit-prs/scripts/babysit_lift.py
  [[ -f "$tool" ]] || return 1
  python3 "$tool" "$1" --repo-dir .base "${@:2}"
}
revert_pass() {
  local c n t repo line message rest lines names unproven='' revert_block
  local -a cs fresh=()
  local -A named=() listed=() prs=() unread=()
  push_range
  local no_revert="no new commit among the ${#pushed[@]} pushed up to ${RUN_SHA:0:12} names a pull request it reverts: no revert record"
  for c in "${pushed[@]}"; do
    message="$(git -C .base log -1 --format=%B "$c" 2>/dev/null)" || message=''
    if [[ -z "$message" && "$c" == "$RUN_SHA" ]]; then
      message="$RUN_COMMIT_MESSAGE"
    fi
    line="${message%%$'\n'*}"
    if [[ "${line%$'\r'}" =~ ^Revert\ \".*\(#([1-9][0-9]*)\)\"(\ \(#[0-9]+\))?$ ]]; then
      prs[$c]+=" ${BASH_REMATCH[1]}"
    fi
    while IFS= read -r line; do
      line="${line%$'\r'}"
      if [[ "$line" =~ ^([-*]\ )?Reverts\ (.*)$ ]]; then
        rest="${BASH_REMATCH[2]}"
        while [[ "$rest" =~ ^([A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+)?#([1-9][0-9]*)(.*)$ ]]; do
          repo="${BASH_REMATCH[1]}" n="${BASH_REMATCH[2]}" rest="${BASH_REMATCH[3]}"
          if [[ "$rest" =~ ^[0-9A-Za-z_] ]]; then
            break
          fi
          if [[ -z "$repo" || "${repo,,}" == "${GITHUB_REPOSITORY,,}" ]]; then
            prs[$c]+=" $n"
          fi
          if [[ ! "$rest" =~ ^(,\ and\ |,\ |\ and\ )(.*)$ ]]; then
            break
          fi
          rest="${BASH_REMATCH[2]}"
        done
      elif [[ "$line" =~ ^This\ reverts\ commit\ ([0-9a-f]{7,40})([^0-9A-Za-z_]|$) ||
        "$line" =~ ^'<!-- red-main-revert culprit='([0-9a-f]{40})' -->'$ ]]; then
        t="${BASH_REMATCH[1]}"
        n="$(subject_pr "$t")"
        if [[ "$n" == '?' ]]; then
          unread[$c]+=" $t"
        elif [[ -n "$n" ]]; then
          prs[$c]+=" $n"
        fi
      fi
    done <<<"$message"
  done
  if ((${#prs[@]} + ${#unread[@]} == 0)); then
    echo "$no_revert"
    return
  fi
  load_records
  while read -r -a cs; do
    for c in "${cs[@]}"; do
      listed[$c]=1
    done
  done < <(awk -F'\t' 'index($4, "<!-- babysit-merge-demotion ") == 1 && index($4, " signal=revert ") { print $6 }' <<<"$records")
  for c in "${pushed[@]}"; do
    if [[ -z "${prs[$c]:-}${unread[$c]:-}" ]]; then
      continue
    fi
    if [[ -n "${listed[$c]+x}" ]]; then
      echo "${c:0:12} is already listed on a revert record"
      continue
    fi
    fresh+=("$c")
    for n in ${prs[$c]:-}; do
      named[$n]=1
    done
    if [[ -n "${unread[$c]:-}" ]]; then
      unproven=1
    fi
  done
  if ((${#fresh[@]} == 0)); then
    echo "$no_revert"
    return
  fi
  reverted=("${!named[@]}")
  reverted_prs="${reverted[*]}"
  if [[ -z "$unproven" ]]; then
    classify
  fi
  if [[ -z "$lane" ]]; then
    echo "no pull request ${RUN_SHA:0:12}'s push reverts was put in the merge queue by the lanes App: no revert record"
    lane=1 reverted=()
    return
  fi
  lines='' names=''
  for n in "${reverted[@]}"; do
    names="${names:+$names, }#$n"
    lines="$lines- Reverted pull request: $repo_url/pull/$n"$'\n'
  done
  for c in "${fresh[@]}"; do
    for t in ${unread[$c]:-}; do
      lines="$lines- Reverted pull request could not be read: commit \`$t\`"$'\n'
    done
  done
  for c in "${fresh[@]}"; do
    lines="$lines- Revert commit: \`$c\`"$'\n'
  done
  revert_block=''
  if [[ -n "$in_checkout" ]]; then
    revert_block="$(lift_block_of revert-block "${fresh[@]}")" || revert_block=''
  fi
  local delim
  delim="EOF_$(openssl rand -hex 16)"
  {
    echo "revert-title=Post-merge revert${names:+ of $names} at ${RUN_SHA:0:12}: unattended merging demoted"
    echo "revert-commits=${fresh[*]}"
    echo "revert-filer=$lane_filer"
    echo "revert-body<<$delim"
    echo "<!-- babysit-merge-demotion sha=$RUN_SHA signal=revert -->

A push to main reverted a pull request the lanes App put in the merge queue, or one whose enqueuer or pull request could not be read. The unattended merge path stays at rung off while this record, or any other demotion record, holds. It lifts once the reverted lines are back on main, or once a pull request that references this record merges into main, re-landing the reverted change or confirming the revert (babysit_merge_policy.py \`_lift\`); a lane then closes it. A person's direct close also clears it.

$lines- Main at the push: \`$RUN_SHA\`
- Canary run: $sighting

Find out why the pull request was reverted, then reference this record from the pull request that re-lands it or confirms the revert.${revert_block:+

$revert_block}"
    echo "$delim"
  } >>"$GITHUB_OUTPUT"
  echo "handed the revert demotion issue for ${RUN_SHA:0:12} to the file-revert job"
  lane=1 reverted=()
}
reverted_prs=''
if [[ "$signal" == canary ]]; then
  revert_pass
  merged_prs=''
  for c in "${pushed[@]}"; do
    n="$(subject_pr "$c")"
    [[ -z "$n" || "$n" == '?' ]] || merged_prs="$merged_prs $n"
  done
  echo "merged-prs=${merged_prs# }" >>"$GITHUB_OUTPUT"
  echo "reverted-prs=$reverted_prs" >>"$GITHUB_OUTPUT"
fi
if [[ -n "$quiet" ]]; then
  echo "$RUN_WORKFLOW concluded $RUN_CONCLUSION on attempt $RUN_ATTEMPT: no canary record to file"
  exit 0
fi
load_records
number=''
state=''
filed=''
has_block=''
while IFS=$'\t' read -r n s _ first failing _; do
  if [[ "$first" == "$marker" || "$first" == "$failure_marker" ||
    ("$first" == "<!-- babysit-merge-demotion "* && "$failing" == "$RUN_URL/attempts/"*) ]]; then
    number="$n"
    state="$s"
    filed="$failing"
    break
  fi
done <<<"$records"
if [[ -n "$number" ]]; then
  has_block="$(awk -F'\t' -v n="$number" '$1 == n && $7 == "block" { print 1; exit }' <<<"$records")"
fi
canary_block=''
if [[ "$signal" == canary && -z "$passed" && -z "$has_block" ]]; then
  push_range
  if [[ -n "$whole_push" ]]; then
    canary_block="$(lift_block_of canary-block "${pushed[@]}")" || canary_block=''
  fi
fi

if [[ -n "$passed" && -z "$number" ]]; then
  echo "attempt $RUN_ATTEMPT passed and no record exists: nothing to file"
  exit 0
fi
if [[ -n "$number" ]]; then
  comments="$(LANE_FILER="$lane_filer" gh api --paginate \
    "repos/$GITHUB_REPOSITORY/issues/$number/comments?per_page=100" \
    --jq '.[] | select(.user.login | IN("github-actions[bot]", env.LANE_FILER)) | .body')"
  if [[ -n "$canary_block" ]] && ! grep -q '^<!-- lift-content v1 ' <<<"$comments"; then
    if gh api -X POST "repos/$GITHUB_REPOSITORY/issues/$number/comments" \
      -f body="$canary_block
The content the canary found deleted, which this record's lift checks on main (babysit_merge_policy.py \`_lift\`)." >/dev/null; then
      echo "recorded the deleted content on #$number"
    else
      echo "::warning::could not record the deleted content on #$number"
    fi
  fi
  if [[ -n "$passed" ]]; then
    note="re-run passed: $sighting"
    if [[ "$filed" != "$RUN_URL/attempts/"* ]] &&
      ! grep -Fq -- "$again$RUN_URL/attempts/" <<<"$comments"; then
      echo "#$number records no failure of $RUN_URL: nothing to note"
      exit 0
    fi
  else
    note="$again$sighting"
  fi
  if grep -Fxq -- "$note" <<<"$comments" || [[ -z "$passed" && "$filed" == "$sighting" ]]; then
    echo "#$number already records $sighting"
    exit 0
  fi
  if [[ -z "$passed" && "$state" != open ]]; then
    gh api -X PATCH "repos/$GITHUB_REPOSITORY/issues/$number" -f state=open >/dev/null
    echo "reopened #$number"
  fi
  gh api -X POST "repos/$GITHUB_REPOSITORY/issues/$number/comments" -f body="$note" >/dev/null
  echo "commented on #$number"
  exit 0
fi

classify
outcome='unattended merging demoted' kind='demotion issue' record_kind=demotion
if [[ -z "$lane" ]]; then
  marker="$failure_marker" outcome='lane not demoted'
  kind='post-merge-failure issue (lane not demoted)' record_kind=failure
fi
pulls="$repo_url/pull"
subject="${RUN_COMMIT_MESSAGE%%$'\n'*}"
pr='unknown (the head commit names none)'
title="Post-merge $signal failure at ${RUN_SHA:0:12}: $outcome"
if [[ "$subject" =~ \(#([0-9]+)\)$ ]]; then
  pr="$pulls/${BASH_REMATCH[1]}"
  title="Post-merge $signal failure after #${BASH_REMATCH[1]}: $outcome"
fi
sha_label='Main at the failing run'
if [[ "$signal" == canary ]]; then
  sha_label='Merge commit'
fi
lead="The post-merge check found a \`$signal\` failure on main."
pr_line="- Pull request: $pr
"
if [[ "${#range[@]}" -gt 1 ]]; then
  lead="$lead It is attributed to the range of ${#range[@]} commits since main's last green full run at \`$base\`, not to one pull request."
  pr_line="- Commits in the range, oldest first:
"
  first='' last='' listed=0
  for c in "${range[@]}"; do
    IFS=$'\t' read -r a s <<<"${entry[$c]}"
    s_shown="${s//\`/}"
    name="${c:0:12}" link="direct push \`${s_shown:0:100}\`, commit"
    if [[ "$s" =~ \(#([0-9]+)\)$ ]]; then
      name="#${BASH_REMATCH[1]}" link="$pulls/${BASH_REMATCH[1]}, merge commit"
    fi
    first="${first:-$name}" last="$name"
    listed=$((listed + 1))
    if [[ "$listed" -le 100 ]]; then
      pr_line="$pr_line  - $link \`$c\`, by $a
"
    fi
  done
  if [[ "$listed" -gt 100 ]]; then
    pr_line="$pr_line  - and $((listed - 100)) more: $repo_url/compare/$base...$RUN_SHA
"
  fi
  title="Post-merge $signal failure after $first..$last: $outcome"
elif [[ "$signal" != canary && "${#range[@]}" -eq 0 ]]; then
  lead="$lead $no_range"
fi
canary_lift="It lifts once the content whose deletion filed it is on main again, or once a pull request that references this record merges into main with that content in its tree (when nothing was deleted, with a canary run passing at its merge commit); a lane then closes it (babysit_merge_policy.py \`_lift\`)."
held="The unattended merge path stays at
rung off while this record holds."
rung="$held It clears once a full run passes on main at a later commit, and a lane then closes it; the fix issues fix main. A new sighting of the same failure reopens it."
if [[ "$signal" == canary && -n "$canary_block" ]]; then
  rung="$held $canary_lift A person's direct close also clears it; a new sighting of the same failure reopens it."
elif [[ "$signal" == canary ]]; then
  rung="$held Only a person's direct close (not through a pull request's closing keyword) clears it, since the deleted content could not be recorded for a lane to check; a new sighting of the same failure reopens it."
fi
if [[ -z "$lane" ]]; then
  not_lane='No merge in it was put in the merge queue by the lanes App, so the lane is NOT demoted and keeps merging'
  canary_hold="$not_lane. A canary failure files no fix issue, so this record keeps Work status needs-human"
  rung="$not_lane; the fix issues fix main."
  if [[ "$signal" == canary && -n "$canary_block" ]]; then
    rung="$canary_hold until it lifts. $canary_lift"
  elif [[ "$signal" == canary ]]; then
    rung="$canary_hold for a person to fix main and close it."
  fi
  if [[ "${#range[@]}" -eq 1 ]]; then
    pr_line="- Pull request: $pr, by ${entry[${range[0]}]%%$'\t'*}
"
  fi
fi
fix_checks=()
fix_over=''
newly_named=''
if [[ -n "$newly" ]]; then
  declare -A fix_seen=()
  while IFS= read -r check; do
    check="${check%%: *}"
    if [[ -n "${fix_seen[$check]+x}" ]]; then
      continue
    fi
    fix_seen[$check]=1
    if fix_name_ok "$check"; then
      newly_named="${newly_named:+$newly_named, }$check"
      if [[ "${#fix_checks[@]}" -lt 5 ]]; then
        fix_checks+=("$check")
        continue
      fi
    fi
    fix_over=1
  done <"$now"
fi
body="$marker

$lead $rung

$pr_line- $sha_label: \`$RUN_SHA\`
- Failing run: $sighting${newly_named:+
- Newly failing: $newly_named}${fix_over:+
- More checks failed than were filed as fix issues: a run files at most 5, and none for a name outside A-Z a-z 0-9 space . _ : , / ( ) -}${canary_block:+

$canary_block}"
record="$(file_issue Bug -f title="$title" -f body="$body")"
if [[ "$signal" == canary || -n "$fix_over" ]]; then
  if [[ ! "$record" =~ ^[1-9][0-9]*$ ]] || ! set_fields "$record" needs-human critical; then
    echo "::error::record '$record' was filed without Work status needs-human"
    exit 1
  fi
elif [[ ! "$record" =~ ^[1-9][0-9]*$ ]] || ! set_fields "$record" needs-triage critical small low known; then
  echo "::warning::could not set the field values of record '$record'"
fi
echo "filed the $signal $kind for $RUN_SHA"

if [[ "${#fix_checks[@]}" -eq 0 ]]; then
  exit 0
fi
if [[ ! "$record" =~ ^[1-9][0-9]*$ || ! "$RUN_ID" =~ ^[1-9][0-9]*$ ]]; then
  echo "::error::record number '$record' or run id '$RUN_ID' is not a number: no fix issue filed"
  exit 1
fi
on_record="$record_kind record #$record"
run_link="$repo_url/actions/runs/$RUN_ID/attempts/$RUN_ATTEMPT"
merges="unknown, see $on_record"
if [[ "${#range[@]}" -gt 0 ]]; then
  merges="\`${base:0:12}..${RUN_SHA:0:12}\`, listed on $on_record"
fi
undelivered=()
for check in "${fix_checks[@]}"; do
  fix_marker="<!-- post-merge-fix check=$check -->"
  note="This check failed on main again at \`$RUN_SHA\`. Merge range: $merges. Run: $run_link"
  fix_work "$check" "$RUN_SHA" "$signal" "$on_record" "$merges" "$run_link" "$fix_marker" "$note"
  if [[ -n "$fix_missed" ]]; then
    marked=''
    if [[ -n "$fix_missed_issue" ]]; then
      mark_undelivered "$fix_missed_issue" "issue=$fix_missed_issue" && marked=1
      mark_undelivered "$record" "issue=$fix_missed_issue" && marked=1
    else
      mark_undelivered "$record" "check=$check" && marked=1
    fi
    if [[ -z "$marked" ]]; then
      fix_missed+=": no marker could be written, so no run retries it"
    fi
    undelivered+=("$fix_missed")
  fi
done
if [[ "${#undelivered[@]}" -gt 0 ]]; then
  note="Fix work not handed to intake on this run. The hand-off failed; the next alert run retries it unless its line says otherwise:"
  for line in "${undelivered[@]}"; do
    note+=$'\n'"- $line"
  done
  gh api -X POST "repos/$GITHUB_REPOSITORY/issues/$record/comments" -f body="$note" >/dev/null ||
    echo "::error::could not comment on record #$record"
  exit 1
fi
