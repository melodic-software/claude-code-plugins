#!/usr/bin/env bash
# An empty service repository whose default branch sets verification: light for planning.
set -euo pipefail

git init -q -b main
git config user.name eval
git config user.email eval@example.invalid
mkdir -p docs/conventions
printf 'verification: light\n' >docs/conventions/planning.yaml
printf '.work/\n' >.gitignore
printf '# reports service\n\nNightly report exports.\n' >README.md
git add -A
git commit -q -m "chore: reports service"

# The level is read from the default branch on origin, so push main to a local bare origin.
mkdir -p .work/origin.git
git init -q --bare -b main .work/origin.git
git remote add origin "$PWD/.work/origin.git"
git push -q origin main
git remote set-head origin main
