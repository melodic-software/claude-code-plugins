#!/usr/bin/env bash
# Seeds the eval workspace with a git repo: a feature branch two commits ahead of the main it forked
# from, main one commit further on, both pushed to an offline origin where PR 512 is an open draft
# (fixtures/gh-forge); the feature branch also carries an unstaged edit, an untracked file, and one
# linked worktree.
set -euo pipefail

git init -q -b main
git config user.name eval
git config user.email eval@example.invalid
mkdir -p src tools
printf 'export const me = () => null;\n' >src/app.ts
printf 'export const other = 1;\n' >src/other.ts
printf '# demo\n' >README.md
git add src README.md
git commit -q -m "chore: seed"

git checkout -q -b fix/null-user
printf 'export const me = () => ({});\n' >src/app.ts
git commit -q -am "fix: return an empty user"
# shellcheck disable=SC2016 # literal backticks
printf '# demo\n\n`me()` returns an empty user.\n' >README.md
git commit -q -am "docs: note the empty user"

git checkout -q main
printf 'export const extra = 1;\n' >src/extra.ts
git add src/extra.ts
git commit -q -m "chore: advance main"
git checkout -q fix/null-user

git worktree add -q ../eval-linked -b feat/linked main
bash "$(dirname "${BASH_SOURCE[0]}")/../fixtures/gh-forge/install.sh" 512 fix/null-user main "fix: return an empty user"

printf 'export const other = 2;\n' >src/other.ts
printf 'scratch\n' >notes.txt
