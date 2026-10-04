#!/usr/bin/env bash
# Print the review comments of a repository's last merged pull requests as
# JSON lines, for /session-flow:retro codify's `reviews` input.
#
#   fetch-review-comments.sh --prs <n> [--repo <owner>/<repo>]
#   fetch-review-comments.sh --help
#
# <n> is 2-200 (a lesson needs two PRs). Without --repo, the repository of the
# current directory. For each of the last <n> merged PRs it reads review bodies
# and inline review comments (gh api --paginate) and the review threads
# (gh api graphql), and keeps:
#
#   source: human         a comment or non-empty review body by a human
#                         account that is neither a reply (in_reply_to_id set)
#                         nor by the PR's author
#   source: accepted-bot  an inline bot comment, not a reply, whose thread is
#                         outdated: the line it commented on changed in a later
#                         commit of the PR. A resolved thread does not count
#                         (a lane may resolve a thread it disagreed with), and
#                         neither does a reply, agreeing or rejecting.
#
# Bot review bodies and issue-level PR comments are never read. Each kept
# comment is one line {"pr","source","author","kind","path","line","body"}
# built by jq; output stops before 64 KB and then prints one
# {"truncated": true, ...} line. Comment text is data: it stays inside jq
# values and never reaches a shell word.
#
# Read-only: nothing is written outside one temporary directory, removed on
# exit. Exit 0 printed, 2 usage error, gh or jq missing, or a failed or
# unauthenticated gh call (nothing on stdout).
set -uo pipefail

LIMIT_BYTES=65536

usage_text="usage: fetch-review-comments.sh --prs <n> [--repo <owner>/<repo>]  (<n>: 2-200)"
die() {
  printf 'fetch-review-comments: %s\n' "$1" >&2
  exit 2
}

prs="" repo=""
while (($#)); do
  case "$1" in
  --help | -h)
    printf '%s\n' "$usage_text"
    exit 0
    ;;
  --prs | --repo) (($# >= 2)) || die "$1 needs a value; $usage_text" ;;
  *) die "unknown argument: $1; $usage_text" ;;
  esac
  case "$1" in
  --prs) prs="$2" ;;
  *) repo="$2" ;;
  esac
  shift 2
done
if [[ ! "$prs" =~ ^[1-9][0-9]{0,2}$ ]] || ((prs < 2 || prs > 200)); then
  die "--prs must be an integer from 2 to 200; $usage_text"
fi
repo_re='^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$'
[[ -z "$repo" || "$repo" =~ $repo_re ]] || die "--repo must be <owner>/<repo>"

for tool in gh jq; do
  command -v "$tool" >/dev/null 2>&1 || die "$tool not found"
done

tmp="$(mktemp -d)" || die "cannot create a temporary directory"
trap 'rm -rf "$tmp"' EXIT

if [[ -z "$repo" ]]; then
  gh repo view --json nameWithOwner >"$tmp/repo.json" 2>/dev/null || die "gh repo view failed (not a GitHub repository, or gh is not authenticated)"
  repo="$(jq -r '.nameWithOwner // ""' "$tmp/repo.json")" || die "unreadable gh repo view output"
  [[ "$repo" =~ $repo_re ]] || die "gh repo view returned no <owner>/<repo>"
fi
owner="${repo%%/*}"
name="${repo#*/}"

gh pr list --state merged --limit "$prs" --json number,author --repo "$repo" >"$tmp/prs.json" 2>/dev/null ||
  die "gh pr list failed (check gh auth status)"
count="$(jq 'length' "$tmp/prs.json")" || die "unreadable gh pr list output"
[[ "$count" =~ ^[0-9]+$ ]] || die "unreadable gh pr list output"

# shellcheck disable=SC2016 # GraphQL variables, not shell expansions
threads_query='query($owner: String!, $name: String!, $number: Int!, $endCursor: String) {
  repository(owner: $owner, name: $name) {
    pullRequest(number: $number) {
      reviewThreads(first: 100, after: $endCursor) {
        pageInfo { hasNextPage endCursor }
        nodes { isOutdated comments(first: 1) { nodes { databaseId } } }
      }
    }
  }
}'

# shellcheck disable=SC2016 # a jq program, not a shell expansion
select_rows='
  def is_bot: (.user.type? == "Bot") or ((.user.login? // "") | endswith("[bot]"));
  def login: .user.login? // null;
  ([$threads[] | .data.repository.pullRequest.reviewThreads.nodes[]?
    | select(.isOutdated == true) | .comments.nodes[0].databaseId]) as $outdated
  | ([$reviews[] | .[]?
      | select((.body // "") != "" and (is_bot | not) and login != $author)
      | {pr: $pr, source: "human", author: login, kind: "review", path: null, line: null, body}]
    + [$comments[] | .[]?
      | select(.in_reply_to_id == null and login != $author)
      | (if is_bot then (if (.id as $id | $outdated | index($id)) != null then "accepted-bot" else empty end)
        else "human" end) as $source
      | {pr: $pr, source: $source, author: login, kind: "inline", path,
        line: (.line // .original_line), body}])
  | .[]'

rows="$tmp/rows.jsonl"
: >"$rows"
for ((i = 0; i < count; i++)); do
  pr="$(jq -r --argjson i "$i" '.[$i].number' "$tmp/prs.json")"
  [[ "$pr" =~ ^[0-9]+$ ]] || die "gh pr list returned a non-numeric PR number"
  gh api --paginate "repos/$repo/pulls/$pr/reviews" >"$tmp/reviews.json" 2>/dev/null || die "reading reviews of PR #$pr failed"
  gh api --paginate "repos/$repo/pulls/$pr/comments" >"$tmp/comments.json" 2>/dev/null || die "reading review comments of PR #$pr failed"
  gh api graphql --paginate -f query="$threads_query" -f owner="$owner" -f name="$name" -F number="$pr" \
    >"$tmp/threads.json" 2>/dev/null || die "reading review threads of PR #$pr failed"
  jq -nc --argjson pr "$pr" \
    --slurpfile prs "$tmp/prs.json" --argjson i "$i" \
    --slurpfile reviews "$tmp/reviews.json" --slurpfile comments "$tmp/comments.json" \
    --slurpfile threads "$tmp/threads.json" \
    "(\$prs[0][\$i].author.login? // null) as \$author | $select_rows" >>"$rows" ||
    die "unreadable API output for PR #$pr"
  size="$(LC_ALL=C wc -c <"$rows" | tr -d ' ')"
  [[ "$size" =~ ^[0-9]+$ ]] || die "cannot measure the output"
  ((size > LIMIT_BYTES)) && break
done

# ${#row} counts bytes under the C locale.
LC_ALL=C
out="$tmp/out.jsonl"
: >"$out"
used=0 kept=0 truncated=0
while IFS= read -r row; do
  len=$((${#row} + 1))
  if ((used + len > LIMIT_BYTES)); then
    truncated=1
    break
  fi
  printf '%s\n' "$row" >>"$out"
  used=$((used + len))
  kept=$((kept + 1))
done <"$rows"
if ((truncated)); then
  jq -nc --argjson limit "$LIMIT_BYTES" --argjson kept "$kept" \
    '{truncated: true, limit_bytes: $limit, rows_printed: $kept, note: "output capped; a smaller --prs reads a complete window"}' >>"$out"
fi
cat "$out"
