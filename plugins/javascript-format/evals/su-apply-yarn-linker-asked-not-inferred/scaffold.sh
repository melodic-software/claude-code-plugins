#!/usr/bin/env bash
# A git repository with a Berry-format yarn.lock, no .yarnrc.yml and no node_modules, and this clone
# declined the pre-commit entry (setup SKILL.md apply: ask the repo's own Yarn for the linker).
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
printf '{\n  "formatter": { "indentStyle": "space" }\n}\n' >biome.json
mkdir -p src
printf 'export const one = 1;\n' >src/app.ts
printf '__metadata:\n  version: 8\n  cacheKey: 10c0\n' >yarn.lock
git add .
git commit -q -m "chore: init"
