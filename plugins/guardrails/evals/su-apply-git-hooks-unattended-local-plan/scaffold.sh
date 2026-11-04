#!/usr/bin/env bash
# A plain git repository with one commit and no hook manager (setup SKILL.md apply install-git-hooks).
set -euo pipefail
if git rev-parse --verify -q HEAD >/dev/null 2>&1; then
  echo 'scaffold: refusing to run inside a repository that has commits' >&2
  exit 1
fi
git init -q -b main .
git config user.email eval@example.invalid
git config user.name eval
printf '# Demo\n' >README.md
git add .
git commit -q -m "chore: init"
