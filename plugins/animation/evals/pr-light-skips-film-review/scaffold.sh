#!/usr/bin/env bash
# A rendered film whose pack check passed in a repository whose default branch sets
# verification: light for the animation plugin.
set -euo pipefail

git init -q -b main
git config user.name eval
git config user.email eval@example.invalid
mkdir -p docs/conventions
printf '.work/\n' >.gitignore
printf 'verification: light\n' >docs/conventions/animation.yaml
mkdir -p film/frames film/boards
printf '# Brief\nA paper boat drifts left to right across a pond in one shot.\n' >film/brief.md
printf '[{"t0": 0, "t1": 4, "pack": "ink-wash"}]\n' >film/shots.json
printf 'pack check: all rows inside their bands\n' >film/check-output.txt

git add -A
git commit -q -m "chore: seed eval fixture"

# The level is read from the default branch on origin, so push main to a local bare origin.
mkdir -p .work/origin.git
git init -q --bare -b main .work/origin.git
git remote add origin "$PWD/.work/origin.git"
git push -q origin main
