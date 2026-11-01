#!/usr/bin/env bash
# A small repository, one commit on main.
set -euo pipefail
git init -q -b main .
git config user.email eval@example.invalid
git config user.name eval
mkdir -p src
printf 'export const add = (a: number, b: number) => a + b;\n' >src/add.ts
git add .
git commit -q -m "feat: add"
