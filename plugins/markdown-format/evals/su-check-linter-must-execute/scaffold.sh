#!/usr/bin/env bash
set -euo pipefail
if git rev-parse --verify -q HEAD >/dev/null 2>&1; then
  echo 'scaffold: refusing to run inside a repository that has commits' >&2
  exit 1
fi
git init -q -b main .
git config user.email eval@example.invalid
git config user.name eval
git config --local checks.markdown-format.format.declined true
git config --local checks.markdown-format.lint.declined true
printf '{\n  "default": true\n}\n' >.markdownlint.jsonc
printf '# Demo\n' >README.md
mkdir -p drafts
printf '# Notes\n' >drafts/notes.md
printf 'drafts/\n' >.gitignore
git add .
git commit -q -m "chore: init"
