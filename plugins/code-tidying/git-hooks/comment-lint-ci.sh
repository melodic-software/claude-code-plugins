#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Run the code-tidying comment lint over a change's whole diff, for any CI system.

Usage: comment-lint-ci.sh <head> <base>

  <head>  the change's head commit (a commit id or any revision that names a commit)
  <base>  the ref the change merges into, such as origin/main or a commit id

Run it from inside the repository's clone, with both commits and their merge
base fetched. It adds a detached worktree at <head> without checking files out,
soft-resets it to the merge base of <head> and <base> so the change is the
staged diff, and takes the files the lint's settings come from as the merge
base holds them: AGENTS.md and CLAUDE.md (the convention-home pointer), then
code-tidying.yaml and code-tidying.local.yaml in the home the merge base names.
So the level, posture and allow list are the base's, and a branch cannot lower
its own level. It runs comment-lint.sh from beside this script there, removes
the worktree, and exits with the lint's status: 0 clean or report-only, 1 a
finding under block.

Needs python3 with pygments importable on PATH.
Exit 2 on a usage error: a missing argument, a revision that names no commit,
or no merge base between the two.
EOF
}

if [[ $# -eq 1 && ("$1" == -h || "$1" == --help) ]]; then
  usage
  exit 0
fi
if [[ $# -ne 2 || "$1" == -* || "$2" == -* ]]; then
  usage >&2
  exit 2
fi

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
entry="$here/comment-lint.sh"
resolver="$here/resolve-convention-home.sh"
[[ -f "$resolver" ]] || resolver="$here/../lib/resolve-convention-home.sh"

fail_usage() {
  echo "comment-lint-ci: $1" >&2
  exit 2
}
repo="$(git rev-parse --show-toplevel 2>/dev/null)" || fail_usage "run it from inside a git clone"
head="$(git -C "$repo" rev-parse --verify --quiet --end-of-options "$1^{commit}")" ||
  fail_usage "<head> '$1' names no commit in this clone"
git -C "$repo" rev-parse --verify --quiet --end-of-options "$2^{commit}" >/dev/null ||
  fail_usage "<base> '$2' names no commit in this clone; fetch it first"
base="$(git -C "$repo" merge-base --end-of-options "$2" "$head")" ||
  fail_usage "'$1' and '$2' share no merge base in this clone; fetch more history"

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

git -C "$repo" worktree add --quiet --no-checkout --detach "$tree" "$head"
git -C "$tree" read-tree "$head"
git -C "$tree" reset --quiet --soft "$base"

from_base() {
  if git -C "$repo" cat-file -e "$base:$1" 2>/dev/null; then
    git -C "$tree" restore --source="$base" --worktree -- "$1"
  fi
}

from_base AGENTS.md
from_base CLAUDE.md
home="$(bash "$resolver" --root "$tree" --ref "$base" 2>/dev/null)" || home=""
if [[ -z "$home" || "$home" == /* || "$home" == *..* ]]; then
  home=docs/conventions
fi
from_base "${home%/}/code-tidying.yaml"
from_base "${home%/}/code-tidying.local.yaml"

cd "$tree"
AI_AGENT=ci sh "$entry"
