#!/usr/bin/env bash
# portability-scope: the GitHub implementation of the view and list reads; every read is a gh call.
set -uo pipefail

usage() {
  cat <<'EOF'
read-pr.sh: read pull-request facts for the `view` and `list` actions.

Usage:
  read-pr.sh view [<pr>] [--repo <owner/repo>] [--diff] [--out <file>]
  read-pr.sh list [--head <branch>] [--head-match <ERE>] [--search <text>]
                  [--state open|closed|merged|all] [--repo <owner/repo>] [--out <file>]

  <pr>          a number, URL or head branch (default: the current branch's PR)
  --repo        OWNER/REPO or HOST/OWNER/REPO
  --diff        print the unified diff instead of the facts
  --head        list PRs from this head branch
  --head-match  list PRs whose head branch matches the ERE
  --search      list PRs the forge's text search matches
  --state       list state (default: open)
  --out         write the output to this file

Exit codes:
  0  success
  1  invalid argument
  2  gh call failed (no pull request for the branch included)
  5  prerequisite missing (gh, jq)
EOF
  exit 0
}

die() {
  printf 'read-pr: %s\n' "$2" >&2
  exit "$1"
}

LIST_FIELDS=number,url,state,isDraft,title,headRefName,baseRefName,mergeCommit,isCrossRepository,headRepositoryOwner

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

if [[ -n "$OUT" ]]; then
  exec >"$OUT" || die 1 "cannot write $(printf '%q' "$OUT")"
fi

if [[ "$ACTION" == list ]]; then
  head_args=()
  [[ -n "$HEAD" ]] && head_args=(--head "$HEAD")
  [[ -n "$SEARCH" ]] && head_args+=(--search "$SEARCH")
  out=$(gh pr list --state "$STATE" --limit 1000 ${head_args[@]+"${head_args[@]}"} ${repo_args[@]+"${repo_args[@]}"} --json "$LIST_FIELDS") ||
    die 2 "gh pr list failed"
  printf '%s' "$out" | jq --arg re "$HEAD_MATCH" '[.[] | select($re == "" or (.headRefName | test($re)))]' ||
    die 1 "--head-match is not a valid regular expression"
  exit 0
fi

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
if [[ "$api_repo" == '{owner}/{repo}' ]]; then
  remote_url=$(git remote get-url origin 2>/dev/null | tr -d '\r')
  remote_host=""
  if [[ "$remote_url" =~ ^[a-z+]+://([^@/]*@)?([^/:]+) ]]; then
    remote_host="${BASH_REMATCH[2]}"
  elif [[ "$remote_url" =~ ^([^@/]*@)?([^/:]+): ]]; then
    remote_host="${BASH_REMATCH[2]}"
  fi
  if [[ "$remote_host" == github.com ]] || { [[ -n "$remote_host" ]] &&
    gh auth status --hostname "$remote_host" >/dev/null 2>&1; }; then
    api_host="$remote_host"
  fi
else
  [[ "$api_repo" =~ ^[A-Za-z0-9-]+/[A-Za-z0-9._-]+$ && ! "${api_repo#*/}" =~ ^\.\.?$ ]] ||
    die 1 "not a valid OWNER/REPO: $(printf '%q' "$api_repo")"
fi
[[ -z "$api_host" || "$api_host" =~ ^[A-Za-z0-9][A-Za-z0-9.-]*(:[0-9]+)?$ ]] ||
  die 1 "not a valid host: $(printf '%q' "$api_host")"
api_host_args=()
[[ -n "$api_host" ]] && api_host_args=(--hostname "$api_host")

api() {
  gh api ${api_host_args[@]+"${api_host_args[@]}"} "$@"
}

if [[ -z "$num" ]]; then
  owner="${api_repo%%/*}"
  head=$(jq -rn --arg b "$branch" '$b | @uri' | tr -d '\r')
  num=$(api "repos/$api_repo/pulls?head=$owner:$head&state=all&per_page=100" |
    jq -r '((map(select(.state == "open")) + .)[0].number) // empty' | tr -d '\r') ||
    die 2 "pull request lookup failed"
  [[ -n "$num" ]] || die 2 "no pull request found for branch $(printf '%q' "$branch")"
fi

work=$(mktemp -d) || die 2 "cannot make a temp directory"
trap 'rm -rf "$work"' EXIT

if [[ "$DIFF" == 1 ]]; then
  if api -H 'Accept: application/vnd.github.diff' "repos/$api_repo/pulls/$num" >"$work/pr.diff" 2>"$work/diff.err"; then
    cat "$work/pr.diff"
    exit 0
  fi
  grep -q '(HTTP 406)' "$work/diff.err" || { cat "$work/diff.err" >&2; die 2 "pull request diff read failed"; }
  range=$(api "repos/$api_repo/pulls/$num" | jq -r '"\(.base.sha // "")...\(.head.sha // "")"' | tr -d '\r') ||
    die 2 "pull request read failed"
  [[ "$range" =~ ^[[:alnum:]]+\.\.\.[[:alnum:]]+$ ]] || die 2 "pull request read returned no base and head sha"
  api -H 'Accept: application/vnd.github.diff' "repos/$api_repo/compare/$range" || die 2 "pull request diff read failed"
  exit 0
fi
api "repos/$api_repo/pulls/$num" >"$work/pull.json" || die 2 "pull request read failed"
for page in $(seq 1 30); do
  page_file="$work/files-$(printf %02d "$page").json"
  api "repos/$api_repo/pulls/$num/files?per_page=100&page=$page" >"$page_file" ||
    die 2 "pull request files read failed"
  (($(jq length "$page_file" | tr -d '\r') < 100)) && break
done

facts=$(cat "$work"/files-*.json | jq -n --slurpfile pull "$work/pull.json" '
  $pull[0] as $p | [inputs | .[]] as $files | {
    number: $p.number,
    url: $p.html_url,
    state: (if $p.merged_at then "MERGED" else ($p.state | ascii_upcase) end),
    isDraft: ($p.draft // false),
    title: $p.title,
    body: ($p.body // ""),
    baseRefName: $p.base.ref,
    headRefName: $p.head.ref,
    baseRefOid: $p.base.sha,
    headRefOid: $p.head.sha,
    isCrossRepository: ($p.head.repo.full_name == null or $p.head.repo.full_name != $p.base.repo.full_name),
    mergeCommit: (if $p.merged_at then {oid: $p.merge_commit_sha} else null end),
    additions: $p.additions,
    deletions: $p.deletions,
    files: [$files[] | {path: .filename, additions, deletions,
      changeType: (if .status == "removed" then "DELETED" else (.status | ascii_upcase) end)}],
    labels: [($p.labels // [])[] | {id: .node_id, name, description, color}]
  }') || die 2 "pull request read returned unexpected JSON"

url=$(printf '%s' "$facts" | jq -r '.url // ""' | tr -d '\r')
host="" repo_path=""
if [[ "$url" =~ ^https?://([^/]+)/([^/]+/[^/]+)/pull/[0-9]+$ ]]; then
  host="${BASH_REMATCH[1]}" repo_path="${BASH_REMATCH[2]}"
fi
visibility=UNKNOWN
if [[ -n "$repo_path" ]] && { [[ "$host" == github.com ]] ||
  env -u GH_ENTERPRISE_TOKEN -u GITHUB_ENTERPRISE_TOKEN gh auth status --hostname "$host" >/dev/null 2>&1; }; then
  v=$(gh api --hostname "$host" "repos/$repo_path" --jq '.visibility' 2>/dev/null | tr -d '\r' | tr '[:lower:]' '[:upper:]')
  [[ "$v" =~ ^(PUBLIC|PRIVATE|INTERNAL)$ ]] && visibility="$v"
fi

printf '%s' "$facts" | jq --arg v "$visibility" '. + {visibility: $v}'
