#!/usr/bin/env bash
# A git repository with no root markdownlint config: a plain docs/ config, a customRules config under tools/,
# a .cjs config under scripts/, and a gitignored node_modules decoy (setup SKILL.md check steps 5 and 9).
set -euo pipefail
if git rev-parse --verify -q HEAD >/dev/null 2>&1; then
  echo 'scaffold: refusing to run inside a repository that has commits' >&2
  exit 1
fi
git init -q -b main .
git config user.email eval@example.invalid
git config user.name eval
git config --local checks.markdown-format.markdown-check.declined true
printf '# Demo\n' >README.md
mkdir -p docs tools scripts node_modules/pkg
printf '# Guide\n' >docs/guide.md
printf '{\n  "default": true\n}\n' >docs/.markdownlint.jsonc
printf '# Tools\n' >tools/notes.md
printf '{\n  "customRules": ["./rule.js"]\n}\n' >tools/.markdownlint-cli2.jsonc
printf 'module.exports = {};\n' >tools/rule.js
printf '# Scripts\n' >scripts/notes.md
printf 'module.exports = {};\n' >scripts/.markdownlint.cjs
printf '{}\n' >node_modules/pkg/.markdownlint.json
printf 'node_modules/\n' >.gitignore
git add .
git commit -q -m "chore: init"
