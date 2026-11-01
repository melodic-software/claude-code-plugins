#!/usr/bin/env bash
# report-escalation.sh: the pr-unblock lane's report-escalation leaf. Ends a
# lane run that stopped, on the route escalation-routes.json (beside this
# script, the one routing table) gives its reason. Run from the base copy; it
# reads only the trusted base checkout and the GitHub API, never a PR head
# file, and never writes to the branch.
#
# - route `hold` (only the owner's three reasons: an intent or design
#   question, a CRITICAL security risk or a billing risk, a person's own
#   thread or hold): hands the PR to a person with one machine-marked comment
#   holding the reason, the resume key and how to resume, plus the
#   human-gated role label. A reason the table does not list holds too, with
#   no activity to resume (fail-safe).
# - route `fail` (a stop the lane's own bounded retries did not mend): no
#   human-gated label; the entry's `label` (needs-session), when it names one,
#   puts the PR in the session-builder queue for a change the lane cannot
#   make, written before the comment. One lanes App comment per activity, marked LANE_STOPPED, is posted
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
#   ESCALATION_REASON   a key of escalation-routes.json; any other well-formed
#                       reason holds for a person
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
  # A refused read prints its JSON error on stdout, which jq would die on with
  # no annotation, so the read is checked before jq sees it.
  gh_error=$(mktemp)
  trap 'rm -f "$gh_error"' EXIT
  if ! statuses=$(gh api --paginate "repos/$GITHUB_REPOSITORY/commits/$HEAD_SHA/statuses?per_page=100" 2>"$gh_error"); then
    message=$(<"$gh_error")
    message=${message//'%'/%25}
    message=${message//$'\r'/%0D}
    message=${message//$'\n'/%0A}
    echo "::error::cannot read the statuses of $HEAD_SHA: $message"
    exit 1
  fi
  state=$(jq -rs --arg c "$context" \
    '[.[][] | select(.context == $c and .creator.login == "github-actions[bot]")][0].state // ""' <<<"$statuses")
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
entry=$(jq -c --arg r "$ESCALATION_REASON" 'if has($r) then .[$r] else null end' "$routes") || die "cannot read $routes"
if [[ $entry == null ]]; then
  # Fail-safe: a reason the table does not list holds for a person, with no
  # activity to resume.
  why="the lane stopped on a reason its routing table does not list, so a person decides"
  activity='' route=hold session_label=''
else
  why=$(jq -er '.why | strings' <<<"$entry") || die "no why for $ESCALATION_REASON in $routes"
  activity=$(jq -er '.activity | strings' <<<"$entry") || die "no activity for $ESCALATION_REASON in $routes"
  route=$(jq -er '.route | select(. == "hold" or . == "fail")' <<<"$entry") || die "no route for $ESCALATION_REASON in $routes"
  # The session-builder queue label a fail-routed reason may name.
  session_label=$(jq -er --arg route "$route" 'if has("label") then .label | strings | select(test("^[a-z]+(-[a-z]+)*$") and $route == "fail") else "" end' <<<"$entry") ||
    die "the label for $ESCALATION_REASON in $routes is not a label name on a fail route"
fi
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
    author { login } reviewThreads(first: 100, after: $endCursor) { nodes { isResolved path line comments(first: 1) { nodes { url } } } pageInfo { hasNextPage endCursor } } } } }'
  MAX_THREAD_PAGES=10
  nodes='[]' cursor='' unread=false read_ok=true lane_pr=false
  for ((page_n = 1; ; page_n++)); do
    args=(-f query="$query" -f owner="${GITHUB_REPOSITORY%%/*}" -f name="${GITHUB_REPOSITORY#*/}" -F number="$PR_NUMBER")
    [[ -n $cursor ]] && args+=(-f endCursor="$cursor")
    if ! page=$(gh api graphql "${args[@]}") ||
      ! nodes=$(jq -ce --argjson acc "$nodes" '$acc + .data.repository.pullRequest.reviewThreads.nodes' <<<"$page") ||
      ! next=$(jq -er '.data.repository.pullRequest.reviewThreads.pageInfo | if .hasNextPage then .endCursor else "" end' <<<"$page"); then
      read_ok=false
      break
    fi
    # The first page names the author: GraphQL gives an App's login without
    # the [bot] suffix. One that does not read is not the lanes App's.
    if ((page_n == 1)) && [[ $(jq -r '.data.repository.pullRequest.author.login // ""' <<<"$page") == "${bot%\[bot\]}" ]]; then
      lane_pr=true
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
elif [[ $ESCALATION_REASON == feedback-incomplete ]]; then
  # Each kept thread with no disposition, as publish-feedback.mjs named it
  # (undisposedLines) in the newest lanes App round marker on this head. Only
  # a line of that exact shape is copied, rebuilt from its id and comment id.
  # When this round's marker failed to post, an earlier round's on the same
  # head is the newest; the run's publish-feedback log names this round's.
  round_marker='<!-- pr-unblock:address-feedback-round -->'
  discussion="${GITHUB_SERVER_URL:-https://github.com}/$GITHUB_REPOSITORY/pull/$PR_NUMBER#discussion_r"
  # shellcheck disable=SC2016  # jq string interpolation, not shell expansions
  if threads=$(gh api --paginate "$issue/comments?per_page=100" | jq -sr --arg bot "$bot" --arg m "$round_marker" \
    --arg on " on $HEAD_SHA." --arg url "$discussion" \
    '[add[] | select(.user.login == $bot) | (.body // "") | split("\n") | map(rtrimstr("\r"))
      | select(.[0] == $m and any(.[]; endswith($on)))] | last // []
      | [.[] | (capture("^- `(?<id>PRRT_[A-Za-z0-9_-]{1,100})` \\(root comment (?<c>[1-9][0-9]{0,18})\\)$") | "- `\(.id)`: \($url)\(.c)"),
        select(test("^- and [1-9][0-9]* more$"))]
      | join("\n")'); then
    [[ -n $threads ]] || threads='- none named in the lane'"'"'s round record on this head; the run'"'"'s publish-feedback log names them'
  else
    threads='- the lane'"'"'s round record could not be read; the run'"'"'s publish-feedback log names them'
  fi
  details=$'\n'"Kept review threads with no disposition:"$'\n\n'"$threads"$'\n'
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
  labels_line='The lane sets no label: the run'
  if [[ -n $session_label ]]; then
    labels_line="The lane labels it \`$session_label\` for a session builder, who makes the change this lane cannot, and the run"
  fi
  more=''
  next_text='When a retry on this head can change the outcome, the lane runs one on its own, up to its per-head cap, and edits this comment if it stops again; a run that does not stop clears the status. When no retry can (a review thread the lane does not take or settle, or a failing check after the retries are spent), a person resolves the threads or gets the checks green, then dispatches the workflow below: that run finds the cause gone and clears the status. On a pull request the lanes App opened, the dispatchers start that run once per stop; on any other, a person does. A new commit to the branch starts clean.'
  if [[ $ESCALATION_REASON == feedback-not-converging && ${lane_pr:-false} == true ]]; then
    # The pr-merge lane closes a lanes App pull request stopped here and
    # re-admits its issue (enable-auto-merge.mjs notConverging).
    next_text="The pr-merge lane closes this pull request on its next run and re-admits its issue for a fresh attempt. To keep it open, first add \`do-not-merge\` (or the human-gated label), then reply on a thread, from an account with write access, starting \`PR-fix lane: please fix this finding\`, which grants one more round on that thread, or resolve the threads and dispatch the workflow below."
  elif [[ $ESCALATION_REASON == feedback-not-converging ]]; then
    more=" A reply on a thread, from an account with write access, starting \`PR-fix lane: please fix this finding\` grants one more round on that thread."
  fi
  cat >"$body" <<EOF
$marker
The pr-unblock lane stopped \`$activity\` on this pull request: $why. $labels_line ends in a failing \`$context\` status on the head the lane gated.

- Reason: \`$ESCALATION_REASON\`
- Head: \`$HEAD_SHA\`
$run_line$details
$next_text$more

To run it again on this head now, dispatch the \`pr-unblock\` workflow:

\`\`\`sh
$dispatch
\`\`\`
EOF
  # The session-builder queue label goes on before the comment that explains it, and back on when
  # a session removed it and the lane stops again with the same comment.
  if [[ -n $session_label ]] && [[ $(gh api "$issue" | jq --arg l "$session_label" '[.labels[].name] | index($l) != null') != true ]]; then
    gh api -X POST "$issue/labels" -f "labels[]=$session_label" >/dev/null
  fi
  id=$(jq -r '.id // empty' <<<"$existing")
  if [[ -n $id && $(jq -r '.body // ""' <<<"$existing" | tr -d '\r') == "$(cat "$body")" ]]; then
    echo "already reported $ESCALATION_REASON on $HEAD_SHA"
    exit 0
  fi
  if [[ -n $id ]]; then
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
  echo "stopped: $ESCALATION_REASON on $HEAD_SHA, ${session_label:-no} label"
  exit 0
fi

if [[ -n $activity ]]; then
  resume="To resume, deal with the reason above, remove the \`$label\` label (and \`do-not-merge\`, if set), then dispatch the \`pr-unblock\` workflow with \`pr-number=$PR_NUMBER\` and \`activity=$activity\`:"$'\n\n```sh\n'"$dispatch"$'\n```'
else
  resume="To resume, deal with the reason above, then remove the \`$label\` label (and \`do-not-merge\`, if set)."
fi
cat >"$body" <<EOF
$marker
$key_line
The pr-unblock lane stopped on this pull request and needs a person: $why.

- Reason: \`$ESCALATION_REASON\`
- Resume key: \`$HEAD_SHA\` (the head the lane stopped on)

$resume
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
