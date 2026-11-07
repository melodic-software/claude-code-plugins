#!/usr/bin/env bash
# Seeds a git repository with a remote, so the report action has a project key
# to look under and nothing saved there.
set -euo pipefail

git init -q -b main
git config user.name dev
git config user.email dev@example.invalid
git remote add origin https://example.invalid/acme/bike-share.git

cat >CLAUDE.md <<'MD'
# Bike share

Dock availability service.

- Build: `make`
- Test: `make test`
MD

git add -A
git commit -q -m "chore: initial commit"
