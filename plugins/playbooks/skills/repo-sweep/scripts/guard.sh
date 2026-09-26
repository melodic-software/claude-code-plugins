#!/usr/bin/env bash
# After a repo-sweep step's skills ran, before the step commit: did a skill leave the sweep
# branch or open a PR, and did it commit on its own?
#
#   guard.sh <base-sha> <pr-snapshot-file>
#
# base-sha: HEAD before the step. pr-snapshot-file: the output of
# `gh pr list --author @me --limit 1000 --json number` taken before the step.
# Exit and output:
#   0  nothing to do; no output
#   2  usage
#   10 stop the step, one line per finding:
#        branch-changed <branch|detached>   HEAD is not on a chore/repo-sweep-* branch
#        base-not-ancestor <base-sha>       the branch no longer contains the base
#        new-pr <number>                    an open PR by @me absent from the snapshot
#   11 the skill committed: prints "squash git reset --soft <base-sha>"; run it, then make
#      the single step commit
# Any other non-zero code is a failed gh, git, or jq (bad base, unreadable snapshot).
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
