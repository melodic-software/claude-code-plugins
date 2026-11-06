#!/usr/bin/env bash
# A rendered demo video whose quality control passed in a repository whose default branch sets
# verification: light for the playwright plugin.
set -euo pipefail

git init -q -b main
git config user.name eval
git config user.email eval@example.invalid
mkdir -p docs/conventions
printf '.work/\n' >.gitignore
printf 'verification: light\n' >docs/conventions/playwright.yaml
mkdir -p work/quality-control
printf 'placeholder\n' >work/demo.mp4
printf '{"fail": 0, "checks": "all PASS"}\n' >work/quality-control/quality-control.json

git add -A
git commit -q -m "chore: seed eval fixture"

# The level is read from the default branch on origin, so push main to a local bare origin.
mkdir -p .work/origin.git
git init -q --bare -b main .work/origin.git
git remote add origin "$PWD/.work/origin.git"
git push -q origin main
