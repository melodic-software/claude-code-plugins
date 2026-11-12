#!/usr/bin/env bash
# A git repository where this clone has declined the pre-commit entry, so check's verify step prints declined and the
# only question is the toggle (setup SKILL.md check step 6 and apply).
set -euo pipefail
if git rev-parse --verify -q HEAD >/dev/null 2>&1; then
  echo 'scaffold: refusing to run inside a repository that has commits' >&2
  exit 1
fi
git init -q -b main .
git config user.email eval@example.invalid
git config user.name eval
git config --local checks.spelling.typos-check.declined true
printf 'A short note with no spelling mistakes.\n' >notes.txt
git add .
git commit -q -m "chore: init"
