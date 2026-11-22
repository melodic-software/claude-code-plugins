#!/usr/bin/env bash
# GENERATED from lib/target-repo.sh by scripts/sync-shared-copies.sh. Do not edit this copy:
# edit the canonical source, then rerun the script.
set -uo pipefail

lower() { printf '%s' "$1" | tr '[:upper:]' '[:lower:]'; }

github_repo_of() {
  local url="${1%/}"
  url="${url%.git}"
  case "$(lower "$url")" in
  https://github.com/*) echo "${url:19}" ;;
  ssh://git@github.com/*) echo "${url:21}" ;;
  git@github.com:*) echo "${url:15}" ;;
  *) ;;
  esac
}

usage() {
  echo "usage: target-repo.sh [--dir <checkout>] [--write]" >&2
  exit 2
}

DIR=.
WRITE=
while [[ $# -gt 0 ]]; do
  case "$1" in
  --dir)
    [[ $# -ge 2 ]] || usage
    DIR="$2"
    shift 2
    ;;
  --write)
    WRITE=1
    shift
    ;;
  *) usage ;;
  esac
done
cd "$DIR" || exit 1

found() {
  if [[ -n "$WRITE" ]]; then
    local push
    push=$(gh api "repos/$1" --jq '.permissions.push' | tr -d '\r') || {
      echo "target-repo: could not read repository $1 from GitHub; see gh's error above." >&2
      exit 1
    }
    if [[ "$push" == false ]]; then
      echo "target-repo: you cannot push to $1, so a write there would land on a repository that is not yours. Run from a checkout of your own repository, or set GH_REPO to it." >&2
      exit 1
    fi
  fi
  echo "target repository: $1" >&2
  echo "$1"
  exit 0
}

if [[ -n "${GH_REPO:-}" ]]; then
  repo="${GH_REPO%/}"
  [[ "$repo" == */*/* ]] && repo="${repo#*/}"
  found "$repo"
fi

ERR_FILE=$(mktemp) || exit 1
trap 'rm -f "$ERR_FILE"' EXIT

VIEW=$(gh repo set-default --view 2>"$ERR_FILE" | tr -d '\r') || {
  cat "$ERR_FILE" >&2
  exit 1
}
if [[ -z "$VIEW" ]] && ! grep -q "No default remote repository has been set" "$ERR_FILE"; then
  echo "target-repo: gh repo set-default --view printed no repository:" >&2
  cat "$ERR_FILE" >&2
  exit 1
fi

SEEN=" "
REPOS=()
for remote in origin $(git remote | grep -vx origin); do
  repo=$(github_repo_of "$(git remote get-url "$remote" 2>/dev/null)")
  [[ -n "$repo" && "$SEEN" != *" $(lower "$repo") "* ]] || continue
  SEEN+="$(lower "$repo") "
  REPOS+=("$repo")
done

if ((${#REPOS[@]} > 1)); then
  for repo in "${REPOS[@]}"; do
    parent=$(gh api "repos/$repo" --jq 'select(.permissions.push == true) | .parent.full_name // empty' | tr -d '\r') || {
      echo "target-repo: could not read repository $repo from GitHub; see gh's error above." >&2
      exit 1
    }
    [[ -n "$parent" ]] || continue
    parent=$(lower "$parent")
    if [[ "$parent" == "$(lower "$VIEW")" || "$SEEN" == *" $parent "* ]]; then
      found "$repo"
    fi
  done
fi

[[ -n "$VIEW" ]] && found "$VIEW"

case ${#REPOS[@]} in
1) found "${REPOS[0]}" ;;
0)
  REPO=$(gh api 'repos/{owner}/{repo}' --jq .full_name | tr -d '\r') && [[ -n "$REPO" ]] || exit 1
  found "$REPO"
  ;;
*)
  {
    echo "target-repo: the remotes name ${#REPOS[@]} GitHub repositories (${REPOS[*]}), none a fork of another that you can push to, and no gh default is set, so gh would pick one by remote name."
    echo "Choose the repository this checkout's issues and pull requests belong to, then run:"
    echo "  gh repo set-default <owner>/<repo>"
  } >&2
  exit 1
  ;;
esac
