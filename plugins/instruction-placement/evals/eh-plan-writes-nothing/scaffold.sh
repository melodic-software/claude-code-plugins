#!/usr/bin/env bash
set -euo pipefail

git init -q -b main
git config user.name eval
git config user.email eval@example.invalid
git config commit.gpgsign false
git remote add origin https://forge.example.invalid/harborline/hub.git

cat > AGENTS.md <<'MD'
# Harborline hub

This repository is the hub: every session on Harborline work starts here. It holds the session start, the tracker for cross-repository work and ignored working material, and nothing else.

## Working material

Scratch files go in `.scratch/`, which is ignored; use it in the main checkout only.
MD
printf '@AGENTS.md\n' > CLAUDE.md
printf '.work/\n' > .gitignore

git add AGENTS.md CLAUDE.md .gitignore
git commit -q -m "seed the hub"
