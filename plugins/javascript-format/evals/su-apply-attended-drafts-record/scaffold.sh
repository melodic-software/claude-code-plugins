#!/usr/bin/env bash
# A git repository whose own config shows its formatter and linter (a .prettierrc.json and an
# eslint.config.js, both named in package.json), with no record and no Biome config. apply drafts
# the fix-cmd and lint-cmd for /toolchain:setup and writes no record itself.
set -euo pipefail
if git rev-parse --verify -q HEAD >/dev/null 2>&1; then
  echo 'scaffold: refusing to run inside a repository that has commits' >&2
  exit 1
fi
git init -q -b main .
git config user.email eval@example.invalid
git config user.name eval
mkdir -p src
printf '{\n  "name": "demo",\n  "version": "0.1.0",\n  "type": "module",\n  "devDependencies": {\n    "eslint": "^9.0.0",\n    "prettier": "^3.0.0"\n  }\n}\n' >package.json
printf '{ "semi": true, "singleQuote": false }\n' >.prettierrc.json
printf 'export default [{ files: ["src/**/*.ts"], rules: { "no-unused-vars": "error" } }];\n' >eslint.config.js
printf 'export const one = 1;\n' >src/app.ts
git add .
git commit -q -m "chore: init"
