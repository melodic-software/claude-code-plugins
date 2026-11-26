#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 2 || ! -f $2 ]]; then
  printf 'usage: guard.sh <base-sha> <pr-snapshot-file>\n' >&2
  exit 2
fi
base=$(git rev-parse -q --verify "$1^{commit}")
now=$(gh pr list --author @me --limit 1000 --json number)
new=$(jq -rn --slurpfile old "$2" --argjson now "$now" '($now - $old[0])[] | "new-pr \(.number)"')

stop=()
branch=$(git symbolic-ref -q --short HEAD || echo detached)
[[ $branch == chore/repo-sweep-* ]] || stop+=("branch-changed $branch")
git merge-base --is-ancestor "$base" HEAD || stop+=("base-not-ancestor $1")
[[ -z $new ]] || while IFS= read -r l; do stop+=("$l"); done <<<"$new"
if ((${#stop[@]})); then
  printf '%s\n' "${stop[@]}"
  exit 10
fi
if (($(git rev-list --count "$base..HEAD") > 0)); then
  printf 'squash git reset --soft %s\n' "$base"
  exit 11
fi
