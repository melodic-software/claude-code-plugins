#!/usr/bin/env bash
# Seeds the eval workspace with a git repo: main and a feature branch one commit ahead of it.
set -euo pipefail

git init -q -b main
git config user.name eval
git config user.email eval@example.invalid
mkdir -p src
printf 'export const me = () => null;\n' > src/app.ts
git add src
git commit -q -m "chore: seed"

git checkout -q -b fix/null-user
printf 'export const me = () => ({});\n' > src/app.ts
git commit -q -am "fix: return an empty user"
