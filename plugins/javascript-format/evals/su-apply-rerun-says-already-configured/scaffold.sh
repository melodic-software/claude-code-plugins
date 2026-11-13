#!/usr/bin/env bash
# A git repository where every check step passes or is INFO on a host with node and jq: a root
# biome.json, a gitignored root node_modules/.bin/biome stub, and this clone declined the pre-commit
# entry, so verify reports declined (setup SKILL.md check step 8).
set -euo pipefail
if git rev-parse --verify -q HEAD >/dev/null 2>&1; then
  echo 'scaffold: refusing to run inside a repository that has commits' >&2
  exit 1
fi
git init -q -b main .
git config user.email eval@example.invalid
git config user.name eval
git config --local checks.javascript-format.biome-check.declined true
printf '/node_modules/\n' >.gitignore
printf '{\n  "name": "demo",\n  "version": "0.1.0"\n}\n' >package.json
printf '{\n  "formatter": { "indentStyle": "space" }\n}\n' >biome.json
mkdir -p src
printf 'export const one = 1;\n' >src/app.ts
mkdir -p node_modules/.bin
printf '#!/bin/sh\necho "Version: 2.0.0"\n' >node_modules/.bin/biome
chmod +x node_modules/.bin/biome
git add .
git commit -q -m "chore: init"
