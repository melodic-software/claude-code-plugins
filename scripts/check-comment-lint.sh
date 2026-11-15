#!/usr/bin/env bash
set -euo pipefail

ENTRY=plugins/code-tidying/git-hooks/comment-lint.sh
HOME_RESOLVER=plugins/code-tidying/lib/resolve-convention-home.sh

usage() {
  cat <<'EOF'
Run the code-tidying comment lint over a pull request's whole diff.

Usage: HEAD_SHA=<40-hex head commit> BASE_REF=<base branch> check-comment-lint.sh

Adds a detached worktree at HEAD_SHA, soft-resets it to the merge base with
origin/<BASE_REF> so the pull request's diff is the staged diff, and takes the
files the lint's settings come from as the merge base holds them: AGENTS.md and
CLAUDE.md (the convention-home pointer), then the home's code-tidying.yaml and
code-tidying.local.yaml, each restored from the merge base or removed when it
has none. So the level, posture and allow list are the base's, not the
branch's. It then runs the lint's git-hook entry there unchanged, removes the
worktree and exits with the entry's status.

On any event but pull_request (GITHUB_EVENT_NAME) it says so and exits 0.
Exit 2 on a usage error.
EOF
}

if [[ "${1:-}" == -h || "${1:-}" == --help ]]; then
  usage
  exit 0
fi
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
tree_real="$(cd "$tree" && pwd -P)"

from_base() {
  local parent
  if git -C "$repo" cat-file -e "$base:$1" 2>/dev/null; then
    git -C "$tree" restore --source="$base" --worktree -- "$1"
    return
  fi
  [[ -e "$tree/$1" || -L "$tree/$1" ]] || return 0
  parent="$(cd "$(dirname "$tree/$1")" && pwd -P)"
  if [[ "$parent" != "$tree_real" && "$parent" != "$tree_real/"* ]]; then
    echo "check-comment-lint: $1 sits behind a symlink that leaves the worktree" >&2
    exit 2
  fi
  rm -f -- "$tree/$1"
}

from_base AGENTS.md
from_base CLAUDE.md
home="$(bash "$tree/$HOME_RESOLVER" --root "$tree" 2>/dev/null)" || home=""
if [[ -z "$home" || "$home" == /* || "$home" == *..* ]]; then
  home=docs/conventions
fi
from_base "${home%/}/code-tidying.yaml"
from_base "${home%/}/code-tidying.local.yaml"

if [[ ! -f "$tree/$ENTRY" ]]; then
  echo "::notice::comment lint declined: $ENTRY is not in the head commit."
  exit 0
fi
cd "$tree"
AI_AGENT=ci sh "$ENTRY"
