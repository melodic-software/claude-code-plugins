#!/usr/bin/env bash
# Seeds what the reassess cases read, after install.sh has given the current checkout a forge:
#   bash reassess-state.sh <number> [--body <text>] [--issue <n> <title> <body>]... [--closes <n>]...
#     [--label <name>]... [--fork <owner>] [--comment <id> <login> <association> <body>]...
#     [--merged <number> <title> <body> <sha>]... [--review <login> <state>]...
# It writes refs/pull/<number>/head in the bare origin (the ref the action fetches), one passing check,
# pr-overlay.json, comments.json, reviews.json and merged-prs.json. The git stand-in install.sh adds records
# each push in calls.jsonl and moves the pull ref with a push to the head branch. --fork takes the head off
# the origin, leaving only the pull ref, as a real fork does. Each --review is one person's review of the
# current head.
# `worktreeroot.path` is set inside the checkout, because a run's Bash can write only under its workspace
# and the action's unpopulated worktree otherwise goes beside the repository.
# shellcheck disable=SC2154 # PR_* come from the state file sourced below
set -euo pipefail

number="$1"
shift
forge="$(git rev-parse --path-format=absolute --git-common-dir)/eval-forge"
origin="$forge/eval-fixture/app.git"
# shellcheck source=/dev/null
source "$forge/state"

body="" fork="" labels='[]' closes='[]' comments='[]' merged='[]' reviews='[]'
while (($#)); do
  case "$1" in
    --body)
      body="$2"
      shift
      ;;
    --issue)
      jq -n --argjson n "$2" --arg title "$3" --arg body "$4" \
        '{number: $n, title: $title, body: $body, state: "OPEN", subIssues: {nodes: []}, url: "https://github.com/eval-fixture/app/issues/\($n)"}' >"$forge/issues/$2.json"
      shift 3
      ;;
    --closes)
      closes=$(jq -c --argjson n "$2" '. + [{number: $n, repository: {name: "app", owner: {login: "eval-fixture"}}, url: "https://github.com/eval-fixture/app/issues/\($n)"}]' <<<"$closes")
      shift
      ;;
    --label)
      labels=$(jq -c --arg l "$2" '. + [{name: $l}]' <<<"$labels")
      shift
      ;;
    --fork)
      fork="$2"
      shift
      ;;
    --comment)
      comments=$(jq -c --argjson id "$2" --arg login "$3" --arg assoc "$4" --arg body "$5" \
        '. + [{id: $id, user: {login: $login, type: "User"}, author_association: $assoc, body: $body, created_at: "2026-11-01T00:00:\($id % 60 | tostring | if length < 2 then "0" + . else . end)Z"}]' <<<"$comments")
      shift 4
      ;;
    --merged)
      merged=$(jq -c --argjson n "$2" --arg title "$3" --arg body "$4" --arg sha "$5" --arg base "$PR_BASE" \
        '. + [{number: $n, title: $title, body: $body, state: "MERGED", mergedAt: "2026-11-01T00:00:00Z", baseRefName: $base,
          headRefName: "merged-\($n)", mergeCommit: {oid: $sha}, commit_shas: [$sha], author: {login: "eval-fixture"},
          url: "https://github.com/eval-fixture/app/pull/\($n)"}]' <<<"$merged")
      shift 4
      ;;
    --review)
      reviews=$(jq -c --arg login "$2" --arg state "$3" --arg sha "$(git -C "$origin" rev-parse "refs/heads/$PR_HEAD")" \
        '. + [{id: (length + 1), user: {login: $login, type: "User"}, author_association: "COLLABORATOR", state: $state, body: "",
          commit_id: $sha, submitted_at: "2026-11-01T00:00:00Z"}]' <<<"$reviews")
      shift 2
      ;;
    *)
      echo "reassess-state.sh: unknown argument '$1'" >&2
      exit 2
      ;;
  esac
  shift
done

git -C "$origin" update-ref "refs/pull/$number/head" "$(git -C "$origin" rev-parse "refs/heads/$PR_HEAD")"
if [[ -n "$fork" ]]; then
  git -C "$origin" update-ref -d "refs/heads/$PR_HEAD"
  git update-ref -d "refs/remotes/origin/$PR_HEAD"
  git branch -q -D "$PR_HEAD"
fi

jq -n '[{name: "ci", state: "SUCCESS", bucket: "pass", workflow: "ci", link: "https://github.com/eval-fixture/app/actions/runs/1"}]' >"$forge/checks"
jq -n --arg body "$body" --argjson labels "$labels" --argjson closes "$closes" --arg fork "$fork" --argjson reviews "$reviews" \
  '{body: $body, labels: $labels, closingIssuesReferences: $closes, reviews: ($reviews | map({author: {login: .user.login}, state}))}
   + (if $fork == "" then {} else {isCrossRepository: true, author: {login: $fork}, headRepositoryOwner: {login: $fork}} end)' >"$forge/pr-overlay.json"
printf '%s\n' "$comments" >"$forge/comments.json"
printf '%s\n' "$reviews" >"$forge/reviews.json"
printf '%s\n' "$merged" >"$forge/merged-prs.json"

git config worktreeroot.path "$PWD/.eval-worktrees"
