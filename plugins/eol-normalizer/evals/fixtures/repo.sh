#!/usr/bin/env bash
# A git repository with one commit. Each argument is one `.gitattributes` line, committed with it;
# with no argument the repository has no `.gitattributes` at all.
set -euo pipefail
git init -q -b main .
git config user.email eval@example.invalid
git config user.name eval
printf '# demo\n' >README.md
if [ "$#" -gt 0 ]; then printf '%s\n' "$@" >.gitattributes; fi
git add .
git commit -q -m "chore: init"
