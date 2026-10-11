#!/usr/bin/env bash
# read-pr.sh — Read pull-request facts for the `view` and `list` actions.
#
# Other skills ask for these reads through `/source-control:pull-request view`
# and `list`, so the forge commands and their field lists live here once.
#
# Usage:
#   read-pr.sh view [<pr>] [--repo <owner/repo>]          # facts as one JSON object
#   read-pr.sh view [<pr>] [--repo <owner/repo>] --diff   # the unified diff
#   read-pr.sh list [--head <branch>] [--head-match <ERE>] [--state open|closed|merged|all]
#                   [--repo <owner/repo>]                 # JSON array, open by default
#
# With no <pr>, `view` reads the current branch's pull request. `view` adds
# `visibility` (PUBLIC, PRIVATE, INTERNAL, or UNKNOWN when the lookup fails).
# `list --head-match` keeps the pull requests whose head branch matches the ERE.
#
# Exit codes:
#   0  success
#   1  invalid argument
#   2  gh call failed (no pull request for the branch included)
#   5  prerequisite missing (gh, jq)

set -uo pipefail

usage() {
  sed -n '2,/^$/p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
  exit 0
}

die() {
  printf 'read-pr: %s\n' "$2" >&2
  exit "$1"
}

VIEW_FIELDS=number,url,state,isDraft,title,baseRefName,headRefName,baseRefOid,headRefOid,additions,deletions,files,labels
LIST_FIELDS=number,url,state,isDraft,title,headRefName,baseRefName,mergeCommit

ACTION="${1:-}"
case "$ACTION" in
-h | --help | "") usage ;;
view | list) shift ;;
*) die 1 "unknown action $(printf '%q' "$ACTION") (use --help)" ;;
esac

PR="" REPO="" DIFF=0 HEAD="" HEAD_MATCH="" STATE=open
while (($# > 0)); do
  case "$1" in
  -h | --help) usage ;;
  --repo | --head | --head-match | --state)
    (($# >= 2)) || die 1 "$1 needs a value"
    [[ "$1" == --repo ]] && REPO="$2"
    [[ "$1" == --head ]] && HEAD="$2"
    [[ "$1" == --head-match ]] && HEAD_MATCH="$2"
    [[ "$1" == --state ]] && STATE="$2"
    shift 2
    ;;
  --diff)
    DIFF=1
    shift
    ;;
  -*) die 1 "unknown flag $(printf '%q' "$1") (use --help)" ;;
  *)
    [[ "$ACTION" == view && -z "$PR" ]] || die 1 "unexpected argument $(printf '%q' "$1")"
    PR="$1"
    shift
    ;;
  esac
done

if [[ "$ACTION" == view && (-n "$HEAD" || -n "$HEAD_MATCH" || "$STATE" != open) ]]; then
  die 1 "--head, --head-match and --state belong to list"
fi
[[ "$ACTION" == list && "$DIFF" == 1 ]] && die 1 "--diff belongs to view"
case "$STATE" in open | closed | merged | all) ;; *) die 1 "--state must be open, closed, merged or all" ;; esac

command -v gh >/dev/null 2>&1 || die 5 "gh not found on PATH"
command -v jq >/dev/null 2>&1 || die 5 "jq not found on PATH"

repo_args=()
[[ -n "$REPO" ]] && repo_args=(--repo "$REPO")

if [[ "$ACTION" == list ]]; then
  head_args=()
  [[ -n "$HEAD" ]] && head_args=(--head "$HEAD")
  # gh pr list returns 30 pull requests unless --limit says otherwise.
  out=$(gh pr list --state "$STATE" --limit 1000 "${head_args[@]}" "${repo_args[@]}" --json "$LIST_FIELDS") ||
    die 2 "gh pr list failed"
  printf '%s' "$out" | jq --arg re "$HEAD_MATCH" '[.[] | select($re == "" or (.headRefName | test($re)))]' ||
    die 1 "--head-match is not a valid regular expression"
  exit 0
fi

pr_args=()
[[ -n "$PR" ]] && pr_args=("$PR")

if [[ "$DIFF" == 1 ]]; then
  gh pr diff "${pr_args[@]}" "${repo_args[@]}" || die 2 "gh pr diff failed"
  exit 0
fi

facts=$(gh pr view "${pr_args[@]}" "${repo_args[@]}" --json "$VIEW_FIELDS") || die 2 "gh pr view failed"

# Visibility over REST: GraphQL is refused in some sandboxed sessions. The host
# and owner/repo come from the pull request's own URL.
url=$(printf '%s' "$facts" | jq -r '.url // ""' | tr -d '\r')
host="" nwo=""
if [[ "$url" =~ ^https?://([^/]+)/([^/]+/[^/]+)/pull/[0-9]+$ ]]; then
  host="${BASH_REMATCH[1]}" nwo="${BASH_REMATCH[2]}"
fi
visibility=UNKNOWN
if [[ -n "$nwo" ]]; then
  host_args=()
  [[ "$host" != github.com ]] && host_args=(--hostname "$host")
  v=$(gh api "${host_args[@]}" "repos/$nwo" --jq '.visibility' 2>/dev/null | tr -d '\r' | tr '[:lower:]' '[:upper:]')
  [[ "$v" =~ ^(PUBLIC|PRIVATE|INTERNAL)$ ]] && visibility="$v"
fi

printf '%s' "$facts" | jq --arg v "$visibility" '. + {visibility: $v}'
