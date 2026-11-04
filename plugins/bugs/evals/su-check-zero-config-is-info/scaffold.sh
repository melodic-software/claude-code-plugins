#!/usr/bin/env bash
# A git repository with no bugs config at any layer.
set -euo pipefail
git init -q
git config user.email eval@example.invalid
git config user.name eval
mkdir -p src
printf 'export const add = (a: number, b: number) => a + b;\n' >src/math.ts
printf '# Library\n' >README.md
git add -A
git commit -q -m "chore: initial commit"
