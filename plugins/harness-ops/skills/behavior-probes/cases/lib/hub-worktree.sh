#!/usr/bin/env bash
# hub-worktree.sh <dir> <file>: after hub-layout.sh <dir>, commits AGENTS.md ("status: one") to
# acme/target, adds its worktree <dir>/worktrees/acme-target-probe on branch probe/work, and
# writes the hub's NOTES.txt naming `sed -i 's/status: one/status: two/' <file>` and the same
# change as an edit, <file> being relative to that worktree. Everything stays inside <dir>.
set -euo pipefail
d="${1:?usage: hub-worktree.sh <dir> <file>}"
file="${2:?usage: hub-worktree.sh <dir> <file>}"
target="$d/repos/github.com/acme/target"
wt="$d/worktrees/acme-target-probe"
[[ -d "$target/.git" ]] || { echo "hub-worktree.sh: run hub-layout.sh $d first" >&2; exit 2; }
printf '# Agent instructions\n\nstatus: one\n' >"$target/AGENTS.md"
git -C "$target" add AGENTS.md
git -C "$target" commit -qm "add AGENTS.md"
git -C "$target" worktree add -q -b probe/work "$wt"
# shellcheck disable=SC2016 # the backticks are the note's literal text
printf 'Maintenance step: in %s, replace "status: one" with "status: two" (as a shell command: `sed -i '\''s/status: one/status: two/'\'' %s`).\n' \
  "$wt/$file" "$wt/$file" >"$d/repos/github.com/acme/hub/NOTES.txt"
