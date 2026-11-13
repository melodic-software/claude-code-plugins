#!/usr/bin/env bash
# A git repository with a root biome.json and a gitignored root node_modules/.bin/biome stub, and
# packages/vendored with its own biome.jsonc and a committed node_modules/.bin/biome stub
# (setup SKILL.md check steps 3-4; hooks/javascript-format.sh refuses a committed node_modules).
set -euo pipefail
if git rev-parse --verify -q HEAD >/dev/null 2>&1; then
  echo 'scaffold: refusing to run inside a repository that has commits' >&2
  exit 1
fi
git init -q -b main .
git config user.email eval@example.invalid
git config user.name eval
mkdir -p packages/vendored/src packages/vendored/node_modules/.bin
printf '/node_modules/\n' >.gitignore
printf '{\n  "name": "demo",\n  "version": "0.1.0"\n}\n' >package.json
printf '{\n  "formatter": { "indentStyle": "space" }\n}\n' >biome.json
mkdir -p node_modules/.bin
printf '#!/bin/sh\necho "Version: 2.0.0"\n' >node_modules/.bin/biome
chmod +x node_modules/.bin/biome
printf '{}\n' >packages/vendored/biome.jsonc
printf 'export const one = 1;\n' >packages/vendored/src/index.ts
printf '#!/bin/sh\necho "Version: 2.0.0"\n' >packages/vendored/node_modules/.bin/biome
chmod +x packages/vendored/node_modules/.bin/biome
git add .
git commit -q -m "chore: init"
