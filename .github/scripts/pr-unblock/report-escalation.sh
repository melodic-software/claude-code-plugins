#!/usr/bin/env bash
# report-escalation.sh: the pr-unblock lane's report-escalation leaf. Ends a
# lane run that stopped, on the route escalation-routes.json (beside this
# script, the one routing table) gives its reason. Run from the base copy; it
# reads only the trusted base checkout and the GitHub API, never a PR head
# file, and never writes to the branch.
#
# - route `hold` (SAFETY, or a question for a person: intent, design, HIGH or
#   CRITICAL security, a person's own hold): hands the PR to a person with
#   one machine-marked comment holding the reason, the resume key and how to
#   resume, plus the human-gated role label.
# - route `fail` (a defect the lane's own bounded retries did not mend): no
#   label. One lanes App comment per activity, marked LANE_STOPPED, is posted
#   once and edited in place after, naming the reason and the head; status
#   mode (below) puts a failing commit status on that head. A new head carries
#   no status, so the lane's next run there starts clean.
#
# Environment:
#   GH_TOKEN            token with pull-requests: write and issues: write
#                       (statuses: write in status mode)
#   GITHUB_REPOSITORY   owner/repo
#   PR_NUMBER           the pull request
#   HEAD_SHA            the gated head; it is the resume key
#   ESCALATION_REASON   a key of escalation-routes.json
#   TRACKER_CONFIG      base .work-item-tracker.json
#                       (default .base/.work-item-tracker.json)
#   LANES_BOT_LOGIN     the lanes App bot login, the only author whose marker
#                       counts (default melodic-automation-lanes[bot])
#
# The role label is config.role_labels["human-gated"]. A missing file or entry
# means needs-human; a present entry that is not a non-empty string fails.
# Hold is idempotent: with the label on the PR and a LANES_BOT_LOGIN marker
# for this resume key and reason, it writes nothing; another reason on the
# same head gets its own comment, so gate-source.mjs reads every reason the
# label holds for. Without the label (a person removed it to resume), it
# escalates again. The label is written before the comment, so a retry after a
# failure between the two finds the label and posts at most one comment. The
# comment write is tried three times, so a transient failure does not leave the
# label without its explanation. Fail writes nothing when its comment already
# reads as it would.
#
# With the argument `clear` (below), it reads ACTIVITY in place of the reason.
#
# With the argument `status`, it instead posts one failing commit status on
# HEAD_SHA for a fail-routed reason, and nothing for a held one: context
# `pr-unblock/conflict` for resolve-conflicts (GitHub starts no pull_request
# workflow on a conflicted PR, so this status is also what shows the head why
# its CI is missing), else `pr-unblock/<activity>`. That mode needs GH_TOKEN
# with statuses: write and reads TARGET_URL (optional, the run).
#
# Exit: 0 when escalated or already escalated; 1 on bad input or API failure.
set -euo pipefail

die() {
  printf 'report-escalation.sh: %s\n' "$*" >&2
  exit 1
}

routes=$(dirname "${BASH_SOURCE[0]}")/escalation-routes.json

# `clear`: an attempt of ACTIVITY on HEAD_SHA ended without a stop (a same-head
# retry landed). When the newest status of the activity's context on the
# head, by github-actions[bot], is a failure or error, it posts success over it, so a
# stop the retry mended no longer fails the head. Needs statuses: write.
if [[ ${1:-} == clear ]]; then
  [[ ${HEAD_SHA:-} =~ ^([0-9a-f]{40}|[0-9a-f]{64})$ ]] || die "HEAD_SHA is not a commit id"
  [[ ${GITHUB_REPOSITORY:-} =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] || die "GITHUB_REPOSITORY is not owner/repo"
  jq -e --arg a "${ACTIVITY:-}" 'any(.[]; .activity == $a)' "$routes" >/dev/null || die "ACTIVITY is not an activity the table routes"
  if [[ $ACTIVITY == resolve-conflicts ]]; then context=pr-unblock/conflict; else context=pr-unblock/$ACTIVITY; fi
  # Every page, newest first, and failure or error, as ci-status reads the same context.
  state=$(gh api --paginate "repos/$GITHUB_REPOSITORY/commits/$HEAD_SHA/statuses?per_page=100" | jq -rs --arg c "$context" \
    '[.[][] | select(.context == $c and .creator.login == "github-actions[bot]")][0].state // ""')
  if [[ $state != failure && $state != error ]]; then
    echo "no failing $context on $HEAD_SHA to clear"
    exit 0
  fi
  args=(-f state=success -f "context=$context" -f "description=The lane ran again on this head and did not stop")
  [[ -n ${TARGET_URL:-} ]] && args+=(-f "target_url=$TARGET_URL")
  gh api -X POST "repos/$GITHUB_REPOSITORY/statuses/$HEAD_SHA" "${args[@]}" >/dev/null
  echo "cleared $context on $HEAD_SHA"
  exit 0
fi
[[ ${ESCALATION_REASON:-} =~ ^[a-z]+(-[a-z]+)*$ ]] || die "unknown escalation reason [${ESCALATION_REASON:-}]"
entry=$(jq -ce --arg r "$ESCALATION_REASON" 'if has($r) then .[$r] else null end' "$routes") ||
  die "unknown escalation reason [$ESCALATION_REASON]"
why=$(jq -er '.why | strings' <<<"$entry") || die "no why for $ESCALATION_REASON in $routes"
activity=$(jq -er '.activity | strings' <<<"$entry") || die "no activity for $ESCALATION_REASON in $routes"
route=$(jq -er '.route | select(. == "hold" or . == "fail")' <<<"$entry") || die "no route for $ESCALATION_REASON in $routes"
[[ ${PR_NUMBER:-} =~ ^[1-9][0-9]*$ ]] || die "PR_NUMBER is not a pull request number"
[[ ${HEAD_SHA:-} =~ ^([0-9a-f]{40}|[0-9a-f]{64})$ ]] || die "HEAD_SHA is not a commit id"
[[ ${GITHUB_REPOSITORY:-} =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] || die "GITHUB_REPOSITORY is not owner/repo"

case ${1:-} in
  '') ;;
  status)
    if [[ $route != fail ]]; then
      echo "no status for $ESCALATION_REASON: it holds for a person"
      exit 0
    fi
    if [[ $activity == resolve-conflicts ]]; then
      context=pr-unblock/conflict
    else
      context=pr-unblock/$activity
    fi
    if [[ $ESCALATION_REASON == unresolved-conflict ]]; then
      description='Conflicts with the base branch; CI does not run until they are resolved'
    else
      description="Lane stopped: $ESCALATION_REASON; checked again on a new head"
    fi
    args=(-f state=failure -f "context=$context" -f "description=$description")
    [[ -n ${TARGET_URL:-} ]] && args+=(-f "target_url=$TARGET_URL")
    gh api -X POST "repos/$GITHUB_REPOSITORY/statuses/$HEAD_SHA" "${args[@]}" >/dev/null
    echo "posted $context failure on $HEAD_SHA"
    exit 0
    ;;
  *) die "unknown mode [$1]" ;;
esac

bot=${LANES_BOT_LOGIN:-melodic-automation-lanes[bot]}
issue="repos/$GITHUB_REPOSITORY/issues/$PR_NUMBER"
dispatch="gh workflow run pr-unblock.yml -R $GITHUB_REPOSITORY -f pr-number=$PR_NUMBER -f activity=$activity"

if [[ $route == hold ]]; then
  tracker=${TRACKER_CONFIG:-.base/.work-item-tracker.json}
  label=needs-human
  if [[ -f $tracker ]]; then
    label=$(jq -er '.config.role_labels // {}
      | if has("human-gated") then .["human-gated"] | strings | select(length > 0) else "needs-human" end' "$tracker") ||
      die "cannot read the human-gated role label from $tracker"
  fi
  marker='<!-- work-items:escalation lane=pr-unblock kind=escalated -->'
  key_line="<!-- pr-unblock resume-key=$HEAD_SHA -->"
  labeled=$(gh api "$issue" | jq --arg l "$label" '[.labels[].name] | index($l) != null')
  if [[ $labeled == true ]]; then
    marked=$(gh api --paginate "$issue/comments?per_page=100" | jq -s --arg bot "$bot" --arg m "$marker" --arg k "$key_line" \
      --arg r "- Reason: \`$ESCALATION_REASON\`" \
      '[add[] | select(.user.login == $bot) | (.body // "") | split("\n") | map(rtrimstr("\r"))
        | select(.[0] == $m and (.[1] // "") == $k and any(.[]; . == $r))] | length > 0')
    if [[ $marked == true ]]; then
      echo "already escalated $ESCALATION_REASON for resume key $HEAD_SHA"
      exit 0
    fi
  fi
else
  # gate-source.mjs LANE_STOPPED: one per activity, edited in place.
  marker="<!-- pr-unblock:lane-stopped activity=$activity -->"
  if [[ $activity == resolve-conflicts ]]; then
    context=pr-unblock/conflict
  else
    context=pr-unblock/$activity
  fi
  existing=$(gh api --paginate "$issue/comments?per_page=100" | jq -sc --arg bot "$bot" --arg m "$marker" \
    '[add[] | select(.user.login == $bot and ((.body // "") | split("\n")[0] | rtrimstr("\r")) == $m)] | last // {} | {id, body}')
fi

# For a review that is not converging: each open review thread. The count
# of rounds is select's (address-feedback.mjs, round markers and model check
# runs), shown on the neutral checks, so the comment gives none of its own. A
# path is data: backticks, line breaks and angle brackets are dropped so it
# stays one code span and cannot open an HTML comment (a marker line).
details=''
if [[ $ESCALATION_REASON == feedback-not-converging ]]; then
  # Page by page, as address-feedback.mjs listThreads reads them: an open
  # thread past the first 100 can be the one that stopped the lane. Anyone
  # who can comment can add threads, so the read stops at MAX_THREAD_PAGES
  # pages and the comment says so.
  # shellcheck disable=SC2016  # GraphQL variables, not shell expansions
  query='query($owner: String!, $name: String!, $number: Int!, $endCursor: String) { repository(owner: $owner, name: $name) { pullRequest(number: $number) {
    reviewThreads(first: 100, after: $endCursor) { nodes { isResolved path line comments(first: 1) { nodes { url } } } pageInfo { hasNextPage endCursor } } } } }'
  MAX_THREAD_PAGES=10
  nodes='[]' cursor='' unread=false read_ok=true
  for ((page_n = 1; ; page_n++)); do
    args=(-f query="$query" -f owner="${GITHUB_REPOSITORY%%/*}" -f name="${GITHUB_REPOSITORY#*/}" -F number="$PR_NUMBER")
    [[ -n $cursor ]] && args+=(-f endCursor="$cursor")
    if ! page=$(gh api graphql "${args[@]}") ||
      ! nodes=$(jq -ce --argjson acc "$nodes" '$acc + .data.repository.pullRequest.reviewThreads.nodes' <<<"$page") ||
      ! next=$(jq -er '.data.repository.pullRequest.reviewThreads.pageInfo | if .hasNextPage then .endCursor else "" end' <<<"$page"); then
      read_ok=false
      break
    fi
    [[ -n $next ]] || break
    if ((page_n >= MAX_THREAD_PAGES)); then
      unread=true
      break
    fi
    cursor=$next
  done
  if [[ $read_ok == true ]] && threads=$(jq -er --argjson unread "$unread" '[.[] | select(.isResolved == false)
      | "- `\((.path // "") | gsub("[`<>]"; "") | gsub("[\r\n]+"; " "))\(if .line then ":\(.line)" else "" end)`: \(.comments.nodes[0].url // "")"]
      | (.[:20] + (if length > 20 then ["- and \(length - 20) more"] else [] end)
        + (if $unread then ["- review threads past the first 1,000 were not read; see the pull request'"'"'s Files changed tab"] else [] end))
      | join("\n")' <<<"$nodes"); then
    [[ -n $threads ]] || threads='- none open now'
  else
    threads='- the open review threads could not be read; see the pull request'"'"'s Files changed tab'
  fi
  details=$'\n'"The review rounds are not converging after the round cap and one fresh fixer round. Open review threads:"$'\n\n'"$threads"$'\n'
fi

body=$(mktemp)
trap 'rm -f "$body"' EXIT

if [[ $route == fail ]]; then
  # The rounds already run keep counting for a capped reason, so a new head
  # meets the cap again; a write-access fix request, or a person resolving
  # the threads, moves a review that is not converging.
  # The run that stopped: each stop names its own, so the comment's last edit
  # is the newest stop's time (the monitoring lane's stalled-PR signal reads
  # it).
  run_line=''
  if [[ ${GITHUB_RUN_ID:-} =~ ^[1-9][0-9]*$ ]]; then
    run_line="- Run: ${GITHUB_SERVER_URL:-https://github.com}/$GITHUB_REPOSITORY/actions/runs/$GITHUB_RUN_ID"$'\n'
  fi
  more=''
  if [[ $ESCALATION_REASON == feedback-not-converging ]]; then
    more=" A reply on a thread, from an account with write access, starting \`PR-fix lane: please fix this finding\` grants one more round on that thread."
  fi
  cat >"$body" <<EOF
$marker
The pr-unblock lane stopped \`$activity\` on this pull request: $why. The lane sets no label: the run ends in a failing \`$context\` status on the head the lane gated.

- Reason: \`$ESCALATION_REASON\`
- Head: \`$HEAD_SHA\`
$run_line$details
When a retry on this head can change the outcome, the lane runs one on its own, up to its per-head cap, and edits this comment if it stops again; a run that does not stop clears the status. When no retry can (a review thread the lane does not take or settle, or a failing check after the retries are spent), a person resolves the threads or gets the checks green, then dispatches the workflow below: that run finds the cause gone and clears the status, which no dispatcher does on its own. A new commit to the branch starts clean.$more

To run it again on this head now, dispatch the \`pr-unblock\` workflow:

\`\`\`sh
$dispatch
\`\`\`
EOF
  id=$(jq -r '.id // empty' <<<"$existing")
  if [[ -n $id ]]; then
    if [[ $(jq -r '.body // ""' <<<"$existing" | tr -d '\r') == "$(cat "$body")" ]]; then
      echo "already reported $ESCALATION_REASON on $HEAD_SHA"
      exit 0
    fi
    [[ $id =~ ^[1-9][0-9]*$ ]] || die "the lane-stopped comment id is not a number"
    gh api -X PATCH "repos/$GITHUB_REPOSITORY/issues/comments/$id" -F "body=@$body" >/dev/null
    echo "stopped: $ESCALATION_REASON on $HEAD_SHA, comment $id edited"
    exit 0
  fi
  for attempt in 1 2 3; do
    gh api -X POST "$issue/comments" -F "body=@$body" >/dev/null && break
    ((attempt < 3)) || die "cannot post the lane-stopped comment after $attempt attempts"
    sleep $((attempt * 5))
  done
  echo "stopped: $ESCALATION_REASON on $HEAD_SHA, no label"
  exit 0
fi

cat >"$body" <<EOF
$marker
$key_line
The pr-unblock lane stopped on this pull request and needs a person: $why.

- Reason: \`$ESCALATION_REASON\`
- Resume key: \`$HEAD_SHA\` (the head the lane stopped on)

To resume, deal with the reason above, remove the \`$label\` label (and \`do-not-merge\`, if set), then dispatch the \`pr-unblock\` workflow with \`pr-number=$PR_NUMBER\` and \`activity=$activity\`:

\`\`\`sh
$dispatch
\`\`\`
EOF

if [[ $labeled != true ]]; then
  gh api -X POST "$issue/labels" -f "labels[]=$label" >/dev/null
fi
for attempt in 1 2 3; do
  gh api -X POST "$issue/comments" -F "body=@$body" >/dev/null && break
  ((attempt < 3)) || die "cannot post the escalation comment after $attempt attempts; the $label label is on"
  sleep $((attempt * 5))
done
echo "escalated: $ESCALATION_REASON, label $label, resume key $HEAD_SHA"
