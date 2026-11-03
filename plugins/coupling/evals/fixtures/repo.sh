#!/usr/bin/env bash
# An empty repository on main with a committer identity; each case scaffold adds its own files.
set -euo pipefail
git init -q -b main .
git config user.email eval@example.invalid
git config user.name eval
printf '# app\n' >README.md
git add .
git commit -q -m "chore: start the repository"
