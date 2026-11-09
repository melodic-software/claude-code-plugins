#!/usr/bin/env bash
# reassess-limits.sh — What limits `reassess` on one pull request.
#
# Prints one `<kind>: <reason>` line per limit. A failed read is a limit, so an
# unread hold never reads as no hold. Run from a checkout of the base repository.
#
#   refused    closed or merged: no verdict
#   label      carries do-not-merge: a verdict, and only the action's own comment may be edited
#   queue      in a merge queue: a verdict and no action
#   stack      a native stack member: a verdict and no action
#   held       a body hold, a member's veto, a live worker lease or a worktree claim: no action
#   moved      the head is no longer --expect-head: no action
#   unread     a read failed: no action
#   no-update  no update on `continue`, though a label or comment may still go on
#              (a fork head, the standards-sync label, a head branch not unique
#              among open pull requests, a person's outstanding change request)
#
# A person's veto follows the merge gate's rule: each owner, member or
# collaborator's newest comment, review or inline comment with text decides.
#
# Usage:
#   reassess-limits.sh <pr> --repo <owner/repo> --state-dir <dir> [--expect-head <sha>]
#
# Exit codes:
#   0  no limit
#   1  invalid argument
#   3  one or more limits, printed on stdout
#   4  refused: closed or merged
#   5  prerequisite missing (gh, jq, git)

# portability-scope: the GitHub implementation of reassess's limits; every forge read is a gh call.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAIM="$SCRIPT_DIR/../../../scripts/worktree-claim.sh"
STANDARDS_SYNC_LABEL=standards-sync
# The merge gate's two patterns; the test holds these equal to babysit-prs'.
BODY_HOLD_RE=$'\\bdo(?:n[\'\u2019]?t| not)\\s+merge\\b|(?:^|\\r)[^\\S\\r\\n]*hold:'
VETO_RE=$'\\bdo(?:n[\'\u2019]?t| not)[\\s-]*merge\\b|\\bdo-not(?!-merge\\b)[\\s-]*merge\\b|(?<!the )(?<!the `)\\bdo-not-merge\\b|(?<=the )do-not-merge\\b(?!\\s*labels?\\b)|(?<=the `)do-not-merge\\b(?!`\\s*labels?\\b)'

die() {
  printf 'reassess-limits: %s\n' "$2" >&2
  exit "$1"
}

PR="" REPO="" STATE_DIR="" EXPECT=""
while (($# > 0)); do
  case "$1" in
  --repo | --state-dir | --expect-head)
    (($# >= 2)) || die 1 "$1 needs a value"
    case "$1" in
    --repo) REPO="$2" ;;
    --state-dir) STATE_DIR="$2" ;;
    --expect-head) EXPECT="$2" ;;
    *) ;;
    esac
    shift 2
    ;;
  -*) die 1 "unknown flag $(printf '%q' "$1")" ;;
  *)
    [[ -z "$PR" ]] || die 1 "unexpected argument $(printf '%q' "$1")"
    PR="$1"
    shift
    ;;
  esac
done
[[ "$PR" =~ ^[0-9]+$ ]] || die 1 "a pull request number is required"
[[ "$REPO" =~ ^[A-Za-z0-9._-]+/[A-Za-z0-9._-]+$ ]] || die 1 "--repo must be owner/repo"
for tool in gh jq git; do
  command -v "$tool" >/dev/null 2>&1 || die 5 "$tool not found on PATH"
done

found=0
limit() {
  printf '%s: %s\n' "$1" "$2"
  found=1
}

facts=$(gh pr view "$PR" -R "$REPO" --json state,isCrossRepository,labels,body,headRefName,headRefOid,headRepositoryOwner) ||
  {
    limit unread "the pull request"
    exit 3
  }
field() { jq -r "$1" <<<"$facts" | tr -d '\r'; }

state=$(field .state)
if [[ "$state" != OPEN ]]; then
  limit refused "the pull request is $state"
  exit 4
fi
head_branch=$(field .headRefName)
fork=$(field .isCrossRepository)

[[ -z "$EXPECT" || "$(field .headRefOid)" == "$EXPECT" ]] || limit moved "the head is no longer $EXPECT"

[[ "$(field '[.labels[]?.name | ascii_downcase] | index("do-not-merge") != null')" != true ]] ||
  limit label "the pull request carries do-not-merge"

body_hold=$(jq -r --arg re "$BODY_HOLD_RE" '.body // "" | test("(?m)" + $re; "i")' <<<"$facts") ||
  limit unread "the pull request body"
[[ "$body_hold" != true ]] || limit held "its body carries a hold"

# shellcheck disable=SC2016 # GraphQL variables, for gh to bind
if queued=$(gh api graphql -F owner="${REPO%/*}" -F name="${REPO#*/}" -F number="$PR" -f query='
  query($owner: String!, $name: String!, $number: Int!) {
    repository(owner: $owner, name: $name) { pullRequest(number: $number) { isInMergeQueue } } }' \
  --jq '.data.repository.pullRequest.isInMergeQueue') && [[ "$queued" == true || "$queued" == false ]]; then
  [[ "$queued" != true ]] || limit queue "the pull request is in a merge queue"
else
  limit unread "its merge queue membership"
fi

if stack=$(gh api "repos/$REPO/pulls/$PR" --jq 'if (.stack | type) == "object" then "yes" else "no" end') &&
  [[ "$stack" == yes || "$stack" == no ]]; then
  [[ "$stack" != yes ]] || limit stack "the pull request is a native stack member"
else
  limit unread "whether it is a stack member"
fi

people='map(select(.user.type == "User" and ((.author_association // "") | ascii_upcase | IN("OWNER", "MEMBER", "COLLABORATOR"))))'
if comments=$(gh api --paginate --slurp "repos/$REPO/issues/$PR/comments?per_page=100") &&
  reviews=$(gh api --paginate --slurp "repos/$REPO/pulls/$PR/reviews?per_page=100") &&
  inline=$(gh api --paginate --slurp "repos/$REPO/pulls/$PR/comments?per_page=100") &&
  vetoers=$(printf '%s\n' "$comments" "$reviews" "$inline" | jq -rs --arg re "$VETO_RE" "
    flatten | $people | map(select((.body // \"\") | test(\"\\\\S\")))
    | group_by(.user.login) | map(max_by(.submitted_at // .created_at))
    | map(select(.body | test(\$re; \"i\")) | .user.login) | join(\", \")") &&
  requesters=$(jq -rs "
    flatten | $people | map(select(.state == \"APPROVED\" or .state == \"CHANGES_REQUESTED\" or .state == \"DISMISSED\"))
    | group_by(.user.login) | map(max_by(.submitted_at)) | map(select(.state == \"CHANGES_REQUESTED\") | .user.login) | join(\", \")" <<<"$reviews"); then
  [[ -z "$vetoers" ]] || limit held "a veto from $vetoers"
  [[ -z "$requesters" ]] || limit no-update "changes requested by $requesters"
else
  limit unread "its comments and reviews"
fi

if [[ -z "$STATE_DIR" ]]; then
  limit unread "the babysit worker lease: no state directory"
else
  repo_key=$(tr '[:upper:]' '[:lower:]' <<<"${REPO/\//__}")
  lease="$STATE_DIR/active-workers/${repo_key}__pr-$PR.json"
  if [[ -e "$lease" ]]; then
    # Babysit writes UTC with microseconds; jq parses it on every platform, and any other offset fails closed.
    if expiry=$(jq -er '.expires_at | sub("\\.[0-9]+"; "") | sub("\\+00:00$"; "Z") | fromdateiso8601' "$lease" 2>/dev/null); then
      ((expiry <= $(date +%s))) || limit held "a live babysit worker lease"
    else
      limit unread "the babysit worker lease"
    fi
  fi
fi

if [[ "$fork" == true ]]; then
  limit no-update "the head is on a fork"
else
  if worktrees=$(git worktree list --porcelain); then
    worktree=""
    while read -r key value; do
      case "$key" in
      worktree) worktree="$value" ;;
      branch)
        [[ "$value" == "refs/heads/$head_branch" ]] || continue
        bash "$CLAIM" check-enter "$worktree" >/dev/null 2>&1
        case $? in
        0) ;;
        3) limit held "the worktree holding its head is unclaimed and may be in use" ;;
        4) limit held "another live session holds a worktree on its head" ;;
        *) limit unread "the claim on the worktree holding its head" ;;
        esac
        ;;
      *) ;;
      esac
    done <<<"${worktrees//$'\r'/}"
  else
    limit unread "the worktree list"
  fi
  if same_head=$(gh pr list -R "$REPO" --state open --head "$head_branch" --limit 100 --json headRepositoryOwner \
    --jq "map(select((.headRepositoryOwner.login // \"\") | ascii_downcase ==\"$(tr '[:upper:]' '[:lower:]' <<<"${REPO%/*}")\")) | length") &&
    [[ "$same_head" =~ ^[0-9]+$ ]]; then
    ((same_head <= 1)) || limit no-update "its head branch is not unique among open pull requests"
  else
    limit unread "whether its head branch is unique"
  fi
fi

[[ "$(jq -r --arg l "$STANDARDS_SYNC_LABEL" '[.labels[]?.name | ascii_downcase] | index($l) != null' <<<"$facts")" != true ]] ||
  limit no-update "it carries the $STANDARDS_SYNC_LABEL label"

((found == 0)) || exit 3
