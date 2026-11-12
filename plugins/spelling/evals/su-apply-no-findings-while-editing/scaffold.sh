#!/usr/bin/env bash
# A git repository that never installed the pre-commit entry, so verify prints missing (setup SKILL.md check step 6). An
# entry's own key set to false opts this clone in over a global decline.
set -euo pipefail
if git rev-parse --verify -q HEAD >/dev/null 2>&1; then
  echo 'scaffold: refusing to run inside a repository that has commits' >&2
  exit 1
fi
git init -q -b main .
git config user.email eval@example.invalid
git config user.name eval
git config --local checks.spelling.typos-check.declined false
printf 'A short note with no spelling mistakes.\n' >notes.txt
git add .
git commit -q -m "chore: init"
