#!/usr/bin/env bash
# An empty repository with a gitignored .work/ for the running-retro ledger.
set -euo pipefail

git init -q -b main .
git config user.email eval@example.invalid
git config user.name eval

printf '# Project instructions\n\nWork in small steps.\n' >CLAUDE.md
printf '.work/\n' >.gitignore
git add .gitignore CLAUDE.md
git commit -q -m "start"
