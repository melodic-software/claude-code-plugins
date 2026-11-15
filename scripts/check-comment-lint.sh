#!/usr/bin/env bash
set -euo pipefail

TEAM_FILE=docs/conventions/code-tidying.yaml
ENTRY=plugins/code-tidying/git-hooks/comment-lint.sh

usage() {
  cat <<'EOF'
Run the code-tidying comment lint over a pull request's whole diff.

Usage: HEAD_SHA=<40-hex head commit> BASE_REF=<base branch> check-comment-lint.sh

Adds a detached worktree at HEAD_SHA, soft-resets it to the merge base with
origin/<BASE_REF> so the pull request's diff is the staged diff, replaces the
worktree's team file with the merge base's copy (the level, posture and allow
list a branch cannot change for itself), runs the lint's git-hook entry there
unchanged, removes the worktree and exits with the entry's status.

On any event but pull_request (GITHUB_EVENT_NAME) it says so and exits 0.
Exit 2 on a usage error.
EOF
}

case "${1:-}" in
-h | --help)
  usage
  exit 0
  ;;
esac
if (($# > 0)); then
  usage >&2
  exit 2
fi

if [[ "${GITHUB_EVENT_NAME:-}" != pull_request ]]; then
  echo "::notice::comment lint declined on a ${GITHUB_EVENT_NAME:-local} event; there is no pull request diff to judge."
  exit 0
fi

if [[ ! "${HEAD_SHA:-}" =~ ^[0-9a-f]{40}$ ]]; then
  echo "check-comment-lint: HEAD_SHA must be a 40-hex commit id" >&2
  exit 2
fi
if [[ ! "${BASE_REF:-}" =~ ^[A-Za-z0-9._/-]+$ || "$BASE_REF" == -* || "$BASE_REF" == *..* ]]; then
  echo "check-comment-lint: BASE_REF must be a branch name" >&2
  exit 2
fi

repo="$(git rev-parse --show-toplevel)"
base="$(git -C "$repo" merge-base --end-of-options "refs/remotes/origin/$BASE_REF" "$HEAD_SHA")"

scratch="$(mktemp -d)"
tree="$scratch/head"
cleanup() {
  status=$?
  git -C "$repo" worktree remove --force "$tree" 2>/dev/null || true
  rm -rf "${scratch:?}"
  git -C "$repo" worktree prune || true
  exit "$status"
}
trap cleanup EXIT

git -C "$repo" worktree add --quiet --detach "$tree" "$HEAD_SHA"
git -C "$tree" reset --quiet --soft "$base"
if git -C "$repo" cat-file -e "$base:$TEAM_FILE" 2>/dev/null; then
  git -C "$repo" show "$base:$TEAM_FILE" >"$tree/$TEAM_FILE"
else
  rm -f "$tree/$TEAM_FILE"
fi

if [[ ! -f "$tree/$ENTRY" ]]; then
  echo "::notice::comment lint declined: $ENTRY is not in the head commit."
  exit 0
fi
cd "$tree"
sh "$ENTRY"
