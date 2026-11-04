#!/usr/bin/env bash
# A git repository opted in by a root config where this clone declined the pre-commit entry (setup SKILL.md
# check steps 1, 3 and 9).
set -euo pipefail
if git rev-parse --verify -q HEAD >/dev/null 2>&1; then
  echo 'scaffold: refusing to run inside a repository that has commits' >&2
  exit 1
fi
git init -q -b main .
git config user.email eval@example.invalid
git config user.name eval
git config --local checks.markdown-format.markdown-check.declined true
printf '{\n  "default": true\n}\n' >.markdownlint.jsonc
printf '# Demo\n' >README.md
git add .
git commit -q -m "chore: init"
