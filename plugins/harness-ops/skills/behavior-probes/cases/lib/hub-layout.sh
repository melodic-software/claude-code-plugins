#!/usr/bin/env bash
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
