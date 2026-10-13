#!/usr/bin/env bash
# read-pr.sh — Read pull-request facts for the `view` and `list` actions.
#
# Other skills ask for these reads through `/source-control:pull-request view`
# and `list`, so the forge commands and their field lists live here once.
#
# Usage:
#   read-pr.sh view [<pr>] [--repo <owner/repo>]          # facts as one JSON object
#   read-pr.sh view [<pr>] [--repo <owner/repo>] --diff   # the unified diff
#   read-pr.sh list [--head <branch>] [--head-match <ERE>] [--search <text>]
#                   [--state open|closed|merged|all] [--repo <owner/repo>]   # JSON array, open by default
#   Either action takes --out <file> to write its output there instead of stdout.
#
# <pr> is a number, a pull request URL, or a head branch; with none, `view`
# reads the current branch's pull request. --repo also takes HOST/OWNER/REPO.
# `view` reads over REST only, so it works where GraphQL is refused, and adds
# `visibility` (PUBLIC, PRIVATE, INTERNAL, or UNKNOWN when the lookup fails).
# `list --head-match` keeps the pull requests whose head branch matches the ERE.
# `list --search` keeps the pull requests the forge's text search matches.
#
# Exit codes:
#   0  success
#   1  invalid argument
#   2  gh call failed (no pull request for the branch included)
#   5  prerequisite missing (gh, jq)

# portability-scope: the GitHub implementation of the view and list reads; every read is a gh call.
set -uo pipefail

usage() {
  sed -n '2,/^$/p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
  exit 0
}

die() {
  printf 'read-pr: %s\n' "$2" >&2
  exit "$1"
}

LIST_FIELDS=number,url,state,isDraft,title,headRefName,baseRefName,mergeCommit

ACTION="${1:-}"
case "$ACTION" in
-h | --help) usage ;;
"") die 1 "no action: view or list (use --help)" ;;
view | list) shift ;;
*) die 1 "unknown action $(printf '%q' "$ACTION") (use --help)" ;;
esac

PR="" REPO="" OUT="" DIFF=0 HEAD="" HEAD_MATCH="" SEARCH="" STATE=open
while (($# > 0)); do
  case "$1" in
  -h | --help) usage ;;
  --repo | --head | --head-match | --search | --state | --out)
    (($# >= 2)) || die 1 "$1 needs a value"
    [[ "$1" == --out ]] && OUT="$2"
    [[ "$1" == --repo ]] && REPO="$2"
    [[ "$1" == --head ]] && HEAD="$2"
    [[ "$1" == --head-match ]] && HEAD_MATCH="$2"
    [[ "$1" == --search ]] && SEARCH="$2"
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

if [[ "$ACTION" == view && (-n "$HEAD" || -n "$HEAD_MATCH" || -n "$SEARCH" || "$STATE" != open) ]]; then
  die 1 "--head, --head-match, --search and --state belong to list"
fi
[[ "$ACTION" == list && "$DIFF" == 1 ]] && die 1 "--diff belongs to view"
case "$STATE" in open | closed | merged | all) ;; *) die 1 "--state must be open, closed, merged or all" ;; esac

command -v gh >/dev/null 2>&1 || die 5 "gh not found on PATH"
command -v jq >/dev/null 2>&1 || die 5 "jq not found on PATH"

repo_args=()
[[ -n "$REPO" ]] && repo_args=(--repo "$REPO")

# Written by the script, not copied out of tool output, so a large diff arrives whole.
if [[ -n "$OUT" ]]; then
  exec >"$OUT" || die 1 "cannot write $(printf '%q' "$OUT")"
fi

if [[ "$ACTION" == list ]]; then
  head_args=()
  [[ -n "$HEAD" ]] && head_args=(--head "$HEAD")
  [[ -n "$SEARCH" ]] && head_args+=(--search "$SEARCH")
  # gh pr list returns 30 pull requests unless --limit says otherwise.
  out=$(gh pr list --state "$STATE" --limit 1000 ${head_args[@]+"${head_args[@]}"} ${repo_args[@]+"${repo_args[@]}"} --json "$LIST_FIELDS") ||
    die 2 "gh pr list failed"
  printf '%s' "$out" | jq --arg re "$HEAD_MATCH" '[.[] | select($re == "" or (.headRefName | test($re)))]' ||
    die 1 "--head-match is not a valid regular expression"
  exit 0
fi

# `view` reads over REST only: sandboxed sessions refuse GraphQL, which
# `gh pr view` and `gh pr diff` use to find the pull request. `{owner}/{repo}`
# is gh's placeholder for the current repository, filled from its git remotes.
api_repo='{owner}/{repo}' api_host=""
if [[ -n "$REPO" ]]; then
  if [[ "$REPO" =~ ^([^/]+)/([^/]+/[^/]+)$ ]]; then
    api_host="${BASH_REMATCH[1]}" api_repo="${BASH_REMATCH[2]}"
  elif [[ "$REPO" =~ ^[^/]+/[^/]+$ ]]; then
    api_repo="$REPO"
  else
    die 1 "--repo must be OWNER/REPO or HOST/OWNER/REPO"
  fi
fi
num="" branch=""
if [[ "$PR" =~ ^[0-9]+$ ]]; then
  num="$PR"
elif [[ "$PR" =~ ^https?://([^/]+)/([^/]+/[^/]+)/pull/([0-9]+)(/.*)?$ ]]; then
  api_host="${BASH_REMATCH[1]}" api_repo="${BASH_REMATCH[2]}" num="${BASH_REMATCH[3]}"
elif [[ -n "$PR" ]]; then
  branch="$PR"
else
  branch=$(git branch --show-current 2>/dev/null | tr -d '\r')
  [[ -n "$branch" ]] || die 2 "no pull request number and no current branch"
fi
api_host_args=()
[[ -n "$api_host" && "$api_host" != github.com ]] && api_host_args=(--hostname "$api_host")

api() {
  gh api ${api_host_args[@]+"${api_host_args[@]}"} "$@"
}

if [[ -z "$num" ]]; then
  # The branch's open pull request when it has one, else its most recent.
  owner="${api_repo%%/*}"
  # A native Windows jq ends its lines in CRLF; the carriage return is dropped.
  head=$(jq -rn --arg b "$branch" '$b | @uri' | tr -d '\r')
  num=$(api "repos/$api_repo/pulls?head=$owner:$head&state=all&per_page=100" |
    jq -r '((map(select(.state == "open")) + .)[0].number) // empty' | tr -d '\r') ||
    die 2 "pull request lookup failed"
  [[ -n "$num" ]] || die 2 "no pull request found for branch $(printf '%q' "$branch")"
fi

if [[ "$DIFF" == 1 ]]; then
  api -H 'Accept: application/vnd.github.diff' "repos/$api_repo/pulls/$num" || die 2 "pull request diff read failed"
  exit 0
fi

work=$(mktemp -d) || die 2 "cannot make a temp directory"
trap 'rm -rf "$work"' EXIT
api "repos/$api_repo/pulls/$num" >"$work/pull.json" || die 2 "pull request read failed"
# The files endpoint pages at 100 and stops at 3000 files.
for page in $(seq 1 30); do
  # Zero-padded so the glob below keeps page order.
  page_file="$work/files-$(printf %02d "$page").json"
  api "repos/$api_repo/pulls/$num/files?per_page=100&page=$page" >"$page_file" ||
    die 2 "pull request files read failed"
  (($(jq length "$page_file" | tr -d '\r') < 100)) && break
done

# The same field names and value shapes `gh pr view --json` prints.
facts=$(cat "$work"/files-*.json | jq -n --slurpfile pull "$work/pull.json" '
  $pull[0] as $p | [inputs | .[]] as $files | {
    number: $p.number,
    url: $p.html_url,
    state: (if $p.merged_at then "MERGED" else ($p.state | ascii_upcase) end),
    isDraft: ($p.draft // false),
    title: $p.title,
    baseRefName: $p.base.ref,
    headRefName: $p.head.ref,
    baseRefOid: $p.base.sha,
    headRefOid: $p.head.sha,
    mergeCommit: (if $p.merged_at then {oid: $p.merge_commit_sha} else null end),
    additions: $p.additions,
    deletions: $p.deletions,
    files: [$files[] | {path: .filename, additions, deletions,
      changeType: (if .status == "removed" then "DELETED" else (.status | ascii_upcase) end)}],
    labels: [($p.labels // [])[] | {id: .node_id, name, description, color}]
  }') || die 2 "pull request read returned unexpected JSON"

# Visibility: the host and owner/repo come from the pull request's own URL.
url=$(printf '%s' "$facts" | jq -r '.url // ""' | tr -d '\r')
host="" repo_path=""
if [[ "$url" =~ ^https?://([^/]+)/([^/]+/[^/]+)/pull/[0-9]+$ ]]; then
  host="${BASH_REMATCH[1]}" repo_path="${BASH_REMATCH[2]}"
fi
visibility=UNKNOWN
if [[ -n "$repo_path" ]]; then
  host_args=()
  [[ "$host" != github.com ]] && host_args=(--hostname "$host")
  v=$(gh api ${host_args[@]+"${host_args[@]}"} "repos/$repo_path" --jq '.visibility' 2>/dev/null | tr -d '\r' | tr '[:lower:]' '[:upper:]')
  [[ "$v" =~ ^(PUBLIC|PRIVATE|INTERNAL)$ ]] && visibility="$v"
fi

printf '%s' "$facts" | jq --arg v "$visibility" '. + {visibility: $v}'
