#!/usr/bin/env bash
# Resolve the GitHub repository a pull-request phase reads and writes, once, so
# every later gh call names it (`-R <owner>/<repo>` for gh pr and gh issue,
# `repos/<owner>/<repo>/...` for gh api) instead of leaving gh to choose.
#
# Resolution order:
#   1. the default `gh repo set-default` recorded for this checkout;
#   2. with none recorded, the one github.com repository the remotes name;
#   3. with no github.com remote at all, gh's own resolution (an Enterprise host).
# Two or more github.com repositories with no recorded default is refused: gh
# would then pick one by remote name, which in a fork checkout can be upstream.
#
# Usage: target-repo.sh [--dir <checkout>]
# Exit 0: owner/repo on stdout, "target repository: owner/repo" on stderr.
# Exit 1: refused or unresolved; the reason, and the fix when there is one, on stderr.
# Exit 2: usage error.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../../lib/github-remote.sh
source "${SCRIPT_DIR}/../../../lib/github-remote.sh"

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

ERR_FILE=$(mktemp) || exit 1
trap 'rm -f "$ERR_FILE"' EXIT

# --view exits 0 whether or not a default is recorded, so read its output.
VIEW=$(gh repo set-default --view 2>"$ERR_FILE" | tr -d '\r') || {
  cat "$ERR_FILE" >&2
  exit 1
}
[[ -n "$VIEW" ]] && found "$VIEW"
if ! grep -q "No default remote repository has been set" "$ERR_FILE"; then
  echo "target-repo: gh repo set-default --view printed no repository:" >&2
  cat "$ERR_FILE" >&2
  exit 1
fi

declare -A SEEN=()
REPOS=()
for remote in $(git remote); do
  repo=$(github_repo_of "$(git remote get-url "$remote" 2>/dev/null)")
  [[ -n "$repo" && -z "${SEEN[${repo,,}]:-}" ]] || continue
  SEEN[${repo,,}]=1
  REPOS+=("$repo")
done

case ${#REPOS[@]} in
1) found "${REPOS[0]}" ;;
0)
  REPO=$(gh api 'repos/{owner}/{repo}' --jq .full_name | tr -d '\r') && [[ -n "$REPO" ]] || exit 1
  found "$REPO"
  ;;
*)
  {
    echo "target-repo: the remotes name ${#REPOS[@]} GitHub repositories (${REPOS[*]}) and no gh default is set, so gh would pick one by remote name."
    echo "Choose the repository this checkout's issues and pull requests belong to, then run:"
    echo "  gh repo set-default <owner>/<repo>"
  } >&2
  exit 1
  ;;
esac
