#!/usr/bin/env bash
# feedback-thread.sh: the review-thread tool of `comments --ci`
# (reference/comments-ci.md). The write runner stages a read-only copy behind a
# wrapper that fixes the environment below, and the skill's Bash may run only
# that wrapper. Every finding body is untrusted data: it is printed, never run.
#
#   list                              the kept threads, as JSON
#   check-paths <path>...             exit 0 when every path is one a kept
#                                     thread names and none is under .github/
#   reply <thread-id> <disposition>   re-read the thread, post the templated
#                                     reply, resolve it when VALID, and log it
#
# The disposition file is JSON in the scratch directory:
#   {"disposition": "VALID" | "INCORRECT" | "UNCERTAIN" | "VALID-defer",
#    "evidence": ["path:line", ...], "fix_sha": "<sha, VALID only>",
#    "note": "<prose>"}
#
# Environment:
#   FEEDBACK_THREADS    the runner's thread file (repository, pr, head_sha,
#                       lane_branch, threads[])
#   FEEDBACK_LOG        the reply log, one JSON object per line
#   FEEDBACK_SCRATCH    the only directory a disposition file may sit in
#   FEEDBACK_WORKSPACE  the checkout evidence paths are checked against
#   GH_TOKEN            the lane token (or GITHUB_TOKEN)
#
# Exit: 0 done; 1 refused (nothing posted); 2 usage or environment;
# 3 skipped because the thread changed since the runner read it.
set -euo pipefail

die() {
  printf 'feedback-thread: %s\n' "$2" >&2
  exit "$1"
}

for var in FEEDBACK_THREADS FEEDBACK_LOG FEEDBACK_SCRATCH FEEDBACK_WORKSPACE; do
  [[ -n ${!var:-} ]] || die 2 "$var is not set"
done
[[ -f $FEEDBACK_THREADS ]] || die 2 "no thread file"
repo=$(jq -er '.repository | select(test("^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$"))' "$FEEDBACK_THREADS") ||
  die 2 "the thread file names no repository"
pr=$(jq -er '.pr | select(type == "number" and . > 0)' "$FEEDBACK_THREADS") || die 2 "the thread file names no PR"

# A path a kept thread names, not under .github/ in any letter case.
allowed() {
  [[ ! ${1,,} =~ ^\.github(/|$) ]] &&
    jq -e --arg p "$1" 'any(.threads[]; .path == $p)' "$FEEDBACK_THREADS" >/dev/null
}

cmd_list() {
  jq '.threads' "$FEEDBACK_THREADS"
}

cmd_check_paths() {
  (($#)) || die 2 "usage: check-paths <path>..."
  local refused=0 path
  for path in "$@"; do
    if ! allowed "$path"; then
      printf 'refused: %s is not a path a kept thread names, or is under .github/\n' "$path" >&2
      refused=1
    fi
  done
  ((refused == 0)) || exit 1
  echo "allowed"
}

THREAD_QUERY='query($id: ID!) { node(id: $id) { ... on PullRequestReviewThread {
  isResolved pullRequest { number } comments(first: 100) { nodes { databaseId body } } } } }'
RESOLVE_MUTATION='mutation($id: ID!) { resolveReviewThread(input: {threadId: $id}) { thread { isResolved } } }'

cmd_reply() {
  (($# == 2)) || die 2 "usage: reply <thread-id> <disposition-file>"
  local id=$1 file=$2
  [[ $id =~ ^PRRT_[A-Za-z0-9_-]{1,100}$ ]] || die 1 "not a review thread id"
  local thread
  thread=$(jq -ec --arg id "$id" '.threads[] | select(.id == $id)' "$FEEDBACK_THREADS") ||
    die 1 "$id is not a kept thread"
  if [[ -f $FEEDBACK_LOG ]] && jq -se --arg id "$id" 'any(.[]; .thread == $id)' "$FEEDBACK_LOG" >/dev/null 2>&1; then
    die 1 "$id already has a reply from this run"
  fi

  local scratch real
  scratch=$(realpath -e "$FEEDBACK_SCRATCH") || die 2 "no scratch directory"
  real=$(realpath -e -- "$file") || die 1 "no disposition file"
  [[ $real == "$scratch"/* && -f $real && ! -L $file ]] || die 1 "the disposition file must be a file in $scratch"
  (($(stat -c %s "$real") <= 16384)) || die 1 "the disposition file is over 16 KiB"

  local d
  d=$(jq -ec '
    def path_line: type == "string" and test("^[A-Za-z0-9_@+.-]+(/[A-Za-z0-9_@+.-]+)*:[1-9][0-9]{0,6}$")
      and (test("(^|/)\\.\\.?(/|:)") | not);
    select(type == "object")
    | select(.disposition | IN("VALID", "INCORRECT", "UNCERTAIN", "VALID-defer"))
    | select((.evidence // []) | type == "array" and length <= 10 and all(path_line))
    | select((.disposition | IN("VALID", "INCORRECT") | not) or ((.evidence // []) | length > 0))
    | select(.note | type == "string" and length > 0 and length <= 2000)
    | select(if .disposition == "VALID" then (.fix_sha | type == "string" and test("^[0-9a-f]{40}$"))
             else (.fix_sha // "") == "" end)
    | {disposition, evidence: (.evidence // []), fix_sha: (.fix_sha // ""), note}' "$real") ||
    die 1 "the disposition file does not match the template: disposition, evidence path:line list (one or more for VALID and INCORRECT), fix_sha for VALID only, note"

  local disposition fix_sha ev
  disposition=$(jq -r .disposition <<<"$d")
  fix_sha=$(jq -r .fix_sha <<<"$d")
  while IFS= read -r ev; do
    [[ -f $FEEDBACK_WORKSPACE/${ev%:*} ]] || die 1 "evidence ${ev%:*} is not a file in the checkout"
  done < <(jq -r '.evidence[]' <<<"$d")

  # A VALID reply names a fix commit on the lane branch, and every file the
  # lane branch changed since the gated head is one a kept thread names.
  if [[ $disposition == VALID ]]; then
    local head lane cmp path
    head=$(jq -er '.head_sha | select(test("^[0-9a-f]{40}$"))' "$FEEDBACK_THREADS") || die 2 "the thread file names no head"
    lane=$(jq -er '.lane_branch | select(test("^[A-Za-z0-9._/-]+$"))' "$FEEDBACK_THREADS") || die 2 "the thread file names no lane branch"
    cmp=$(gh api "repos/$repo/compare/$head...$lane") || die 1 "cannot compare the lane branch with the gated head"
    jq -e --arg sha "$fix_sha" 'any(.commits[]; .sha == $sha)' <<<"$cmp" >/dev/null ||
      die 1 "the fix $fix_sha is not a commit on the lane branch"
    (($(jq '.files | length' <<<"$cmp") < 300)) || die 1 "the lane branch changes too many files to check"
    while IFS= read -r path; do
      allowed "$path" || die 1 "the lane branch changes $path, which no kept thread names or which is under .github/; no reply is posted"
    done < <(jq -r '.files[] | .filename, (.previous_filename // empty)' <<<"$cmp")
  fi

  # Re-read the thread; anything changed since the runner read it is skipped.
  local now want got
  now=$(gh api graphql -f query="$THREAD_QUERY" -f id="$id") || die 1 "cannot re-read $id"
  want=$(jq -c '[.comments[] | {id, body}]' <<<"$thread")
  got=$(jq -c '[.data.node.comments.nodes[] | {id: .databaseId, body}]' <<<"$now")
  if [[ $(jq -r '.data.node.isResolved' <<<"$now") != false ||
    $(jq -r '.data.node.pullRequest.number' <<<"$now") != "$pr" || $want != "$got" ]]; then
    echo "skipped: $id changed since the run read it" >&2
    exit 3
  fi

  local label body fence
  case $disposition in
    VALID) label='VALID, fixed' ;;
    INCORRECT) label='INCORRECT, left open' ;;
    UNCERTAIN) label='UNCERTAIN, left open for a person' ;;
    VALID-defer) label='VALID (defer), left open for a person' ;;
  esac
  # The note is model prose that quotes untrusted text: control characters
  # go, mentions and HTML comments are broken with a word joiner, the lane
  # token is cut out, and it sits in a fence longer than any backtick run.
  body=$(jq -r --arg label "$label" --arg t1 "${GH_TOKEN:-}" --arg t2 "${GITHUB_TOKEN:-}" '
    def redact($t): if $t == "" then . else split($t) | join("[REDACTED]") end;
    (.note | explode | map(select(. == 9 or . == 10 or (. >= 32 and . != 127))) | implode | gsub("@"; "@⁠")
      | gsub("<!--"; "<⁠!--") | gsub("-->"; "-⁠->") | redact($t1) | redact($t2)) as $note
    | ("`" * ([3, ([$note | scan("`+") | length] | max // 0) + 1] | max)) as $fence
    | [ "**pr-unblock / address-feedback: \($label)**", "",
        (if (.evidence | length) > 0 then "Evidence: " + (.evidence | map("`\(.)`") | join(", ")) else "Evidence: none in the checkout" end),
        (if .fix_sha != "" then "Fix: \(.fix_sha)" else empty end),
        "", "\($fence)text", $note, $fence ] | join("\n")' <<<"$d")

  local root reply
  root=$(jq -r '.root_comment_id' <<<"$thread")
  [[ $root =~ ^[1-9][0-9]*$ ]] || die 2 "the thread file holds no root comment id"
  reply=$(jq -n --arg body "$body" '{body: $body}' | gh api -X POST "repos/$repo/pulls/$pr/comments/$root/replies" --input -) ||
    die 1 "cannot post the reply on $id"
  local reply_id
  reply_id=$(jq -er --argjson root "$root" 'select(.in_reply_to_id == $root) | .id' <<<"$reply") ||
    die 1 "the reply on $id did not land on its thread"

  local resolved=false
  if [[ $disposition == VALID ]]; then
    [[ $(gh api graphql -f query="$RESOLVE_MUTATION" -f id="$id" --jq '.data.resolveReviewThread.thread.isResolved') == true ]] ||
      die 1 "replied on $id but it does not read resolved"
    resolved=true
  fi
  jq -nc --arg thread "$id" --arg disposition "$disposition" --arg sha "$fix_sha" --argjson reply "$reply_id" \
    --argjson resolved "$resolved" '{thread: $thread, disposition: $disposition, fix_sha: $sha, reply_id: $reply, resolved: $resolved}' \
    >>"$FEEDBACK_LOG"
  echo "replied on $id ($disposition)$([[ $resolved == true ]] && echo '; resolved')"
}

case ${1:-} in
  list) cmd_list ;;
  check-paths) shift && cmd_check_paths "$@" ;;
  reply) shift && cmd_reply "$@" ;;
  *) die 2 "usage: feedback-thread.sh list | check-paths <path>... | reply <thread-id> <disposition-file>" ;;
esac
