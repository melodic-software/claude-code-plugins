#!/usr/bin/env bash
set -uo pipefail

github_repo_of() {
  local url="${1%/}"
  url="${url%.git}"
  case "${url,,}" in
  https://github.com/*) echo "${url:19}" ;;
  ssh://git@github.com/*) echo "${url:21}" ;;
  git@github.com:*) echo "${url:15}" ;;
  *) ;;
  esac
}

usage() {
  echo "usage: target-repo.sh [--dir <checkout>]" >&2
  exit 2
}

DIR=.
while [[ $# -gt 0 ]]; do
  case "$1" in
  --dir)
    [[ $# -ge 2 ]] || usage
    DIR="$2"
    shift 2
    ;;
  *) usage ;;
  esac
done
cd "$DIR" || exit 1

found() {
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

declare -A SEEN=()
REPOS=()
for remote in origin $(git remote | grep -vx origin); do
  repo=$(github_repo_of "$(git remote get-url "$remote" 2>/dev/null)")
  [[ -n "$repo" && -z "${SEEN[${repo,,}]:-}" ]] || continue
  SEEN[${repo,,}]=1
  REPOS+=("$repo")
done

if ((${#REPOS[@]} > 1)); then
  for repo in "${REPOS[@]}"; do
    parent=$(gh api "repos/$repo" --jq 'select(.permissions.push == true) | .parent.full_name // empty' | tr -d '\r') || {
      echo "target-repo: could not read repository $repo from GitHub; see gh's error above." >&2
      exit 1
    }
    [[ -n "$parent" ]] || continue
    if [[ "${parent,,}" == "${VIEW,,}" || -n "${SEEN[${parent,,}]:-}" ]]; then
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
