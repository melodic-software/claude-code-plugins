#!/usr/bin/env bash
# A git repository whose only Biome file is a hidden .biome.json, so no config governs it, and this
# clone declined the pre-commit entry (setup SKILL.md check steps 3, 4 and 8).
set -euo pipefail
if git rev-parse --verify -q HEAD >/dev/null 2>&1; then
  echo 'scaffold: refusing to run inside a repository that has commits' >&2
  exit 1
fi
git init -q -b main .
git config user.email eval@example.invalid
git config user.name eval
git config --local checks.javascript-format.biome-check.declined true
printf '{\n  "name": "demo",\n  "version": "0.1.0"\n}\n' >package.json
mkdir -p src
printf 'export const one = 1;\n' >src/app.ts
printf '{}\n' >.biome.json
git add .
git commit -q -m "chore: init"
