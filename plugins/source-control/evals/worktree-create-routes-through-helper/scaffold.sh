#!/usr/bin/env bash
# Seeds the eval workspace with a git repo: one commit on main, a feature branch carrying a staged
# edit, an unstaged edit, an untracked file, and one linked worktree. The project settings set
# worktree.baseRef so the sandbox's denied user settings do not decide the base.
set -euo pipefail

git init -q -b main
git config user.name eval
git config user.email eval@example.invalid
mkdir -p src tools .claude
printf 'export const me = () => null;\n' > src/app.ts
printf 'export const other = 1;\n' > src/other.ts
printf '# demo\n' > README.md
printf '{"worktree":{"baseRef":"fresh"}}\n' > .claude/settings.json
git add src README.md .claude/settings.json
git commit -q -m "chore: seed"

git checkout -q -b fix/null-user
printf 'export const me = () => ({});\n' > src/app.ts
git add src/app.ts
printf 'export const other = 2;\n' > src/other.ts
printf 'scratch\n' > notes.txt

git worktree add -q ../eval-linked -b feat/linked main
