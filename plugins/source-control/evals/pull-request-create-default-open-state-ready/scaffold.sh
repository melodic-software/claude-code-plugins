#!/usr/bin/env bash
# Seeds the eval workspace with a git repo whose feature branch is one commit ahead of main and a
# bare local origin so the push step succeeds. No docs/conventions/source-control.yaml exists, so
# pr_open_state comes from its default, ready.
set -euo pipefail

git init -q --bare ../eval-origin.git
git init -q -b main
git config user.name eval
git config user.email eval@example.invalid
git remote add origin ../eval-origin.git
mkdir -p src
printf 'export const me = () => null;\n' >src/app.ts
printf '# demo\n' >README.md
git add src README.md
git commit -q -m "chore: seed"
git push -q -u origin main

git checkout -q -b fix/null-user
printf 'export const me = () => ({});\n' >src/app.ts
git add src/app.ts
git commit -q -m "fix: return an empty user instead of null"
