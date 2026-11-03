#!/usr/bin/env bash
# Seeds the eval workspace with a git repo: main and a feature branch one commit ahead of it, both
# pushed to an offline origin where PR 517 is open with no checks, comments or review threads yet
# (fixtures/gh-forge). The session starts on the PR branch, so the monitor's checkout step is a no-op.
set -euo pipefail

git init -q -b main
git config user.name eval
git config user.email eval@example.invalid
mkdir -p src
printf 'export const total = (xs) => xs.reduce((a, b) => a + b);\n' >src/sum.ts
git add src
git commit -q -m "chore: seed"

git checkout -q -b fix/empty-total
printf 'export const total = (xs) => xs.reduce((a, b) => a + b, 0);\n' >src/sum.ts
git commit -q -am "fix: total of an empty list is zero"

bash "$(dirname "${BASH_SOURCE[0]}")/../fixtures/gh-forge/install.sh" 517 fix/empty-total main "fix: total of an empty list is zero" \
  --open
