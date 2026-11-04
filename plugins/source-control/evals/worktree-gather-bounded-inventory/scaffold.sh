#!/usr/bin/env bash
# Seeds the eval workspace with a git repo: one commit on main and one linked worktree.
set -euo pipefail

git init -q -b main
git config user.name eval
git config user.email eval@example.invalid
printf '# demo\n' > README.md
git add README.md
git commit -q -m "chore: seed"

git worktree add -q ../eval-linked -b feat/linked main
