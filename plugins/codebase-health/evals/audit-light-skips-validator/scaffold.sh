#!/usr/bin/env bash
# A one-file repository with a planted doc claim in a repository whose default branch sets
# verification: light for the codebase-health plugin.
set -euo pipefail

git init -q -b main
git config user.name eval
git config user.email eval@example.invalid
mkdir -p docs/conventions
printf '.work/\n' >.gitignore
printf 'verification: light\n' >docs/conventions/codebase-health.yaml
cat >README.md <<'MD'
# Tally

Run the tests with `make test`. Configuration lives in `tally.toml`.
MD
printf 'print("tally")\n' >tally.py

git add -A
git commit -q -m "chore: seed eval fixture"

# The level is read from the default branch on origin, so push main to a local bare origin.
mkdir -p .work/origin.git
git init -q --bare -b main .work/origin.git
git remote add origin "$PWD/.work/origin.git"
git push -q origin main
