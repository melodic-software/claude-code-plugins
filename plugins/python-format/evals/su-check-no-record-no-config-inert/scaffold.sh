#!/usr/bin/env bash
# A git repository with Python files, no python record and no Ruff config, so both concerns
# resolve to nothing: the plugin is inert by design.
set -euo pipefail
if git rev-parse --verify -q HEAD >/dev/null 2>&1; then
  echo 'scaffold: refusing to run inside a repository that has commits' >&2
  exit 1
fi
git init -q -b main .
git config user.email eval@example.invalid
git config user.name eval
mkdir -p src
printf 'def main():\n    return 1\n' >src/app.py
git add .
git commit -q -m "chore: init"
