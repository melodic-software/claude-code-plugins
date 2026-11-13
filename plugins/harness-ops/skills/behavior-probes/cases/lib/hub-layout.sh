#!/usr/bin/env bash
# hub-layout.sh <dir>: a clone root <dir>/repos in github.com/<owner>/<repo> layout holding
# two repos, acme/hub and acme/target, each with one commit of README.md ("status: one"),
# and an empty worktrees root <dir>/worktrees. Everything stays inside <dir>.
set -euo pipefail
d="$1"
mkdir -p "$d/worktrees"
for name in hub target; do
  repo="$d/repos/github.com/acme/$name"
  mkdir -p "$repo"
  git -C "$repo" init -q -b main
  git -C "$repo" config user.email probe@example.invalid
  git -C "$repo" config user.name probe
  git -C "$repo" config commit.gpgsign false
  printf '# %s\n\nstatus: one\n' "$name" >"$repo/README.md"
  git -C "$repo" add README.md
  git -C "$repo" commit -qm "initial $name"
done
