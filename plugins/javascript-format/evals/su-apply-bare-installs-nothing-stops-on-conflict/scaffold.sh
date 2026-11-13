#!/usr/bin/env bash
# A git repository with no Biome config whose package-lock.json contradicts the packageManager
# field, and this clone declined the pre-commit entry (setup SKILL.md apply).
set -euo pipefail
if git rev-parse --verify -q HEAD >/dev/null 2>&1; then
  echo 'scaffold: refusing to run inside a repository that has commits' >&2
  exit 1
fi
git init -q -b main .
git config user.email eval@example.invalid
git config user.name eval
git config --local checks.javascript-format.biome-check.declined true
printf '{\n  "name": "demo",\n  "version": "0.1.0",\n  "packageManager": "pnpm@9.15.0"\n}\n' >package.json
printf '{\n  "name": "demo",\n  "version": "0.1.0",\n  "lockfileVersion": 3,\n  "packages": {}\n}\n' >package-lock.json
mkdir -p src
printf 'export const one = 1;\n' >src/app.ts
git add .
git commit -q -m "chore: init"
