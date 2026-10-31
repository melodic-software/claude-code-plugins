#!/usr/bin/env bash
# Seeds the eval workspace with a git repo whose feature branch is one commit ahead of main and an
# offline forge (fixtures/gh-forge, --no-pr) that takes the push, opens the PR and marks it ready. No
# docs/conventions/source-control.yaml exists, so pr_open_state comes from its default, ready.
set -euo pipefail

git init -q -b main
git config user.name eval
git config user.email eval@example.invalid
mkdir -p src
printf 'export const me = () => null;\n' >src/app.ts
printf '# demo\n' >README.md
git add src README.md
git commit -q -m "chore: seed"

git checkout -q -b fix/null-user
printf 'export const me = () => ({});\n' >src/app.ts
git add src/app.ts
git commit -q -m "fix: return an empty user instead of null"
bash "$(dirname "${BASH_SOURCE[0]}")/../fixtures/gh-forge/install.sh" 832 fix/null-user main "fix: return an empty user instead of null" --no-pr
