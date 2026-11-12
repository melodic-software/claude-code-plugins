#!/usr/bin/env bash
# A git repository where every check step passes or is INFO on a host with node and typos: a typos config exists and
# this clone declined the pre-commit entry, so verify prints declined (setup SKILL.md check steps 2, 3, 5 and 6).
set -euo pipefail
if git rev-parse --verify -q HEAD >/dev/null 2>&1; then
  echo 'scaffold: refusing to run inside a repository that has commits' >&2
  exit 1
fi
git init -q -b main .
git config user.email eval@example.invalid
git config user.name eval
git config --local checks.spelling.typos-check.declined true
printf '[files]\nextend-exclude = []\n' >_typos.toml
printf 'A short note with no spelling mistakes.\n' >notes.txt
git add .
git commit -q -m "chore: init"
