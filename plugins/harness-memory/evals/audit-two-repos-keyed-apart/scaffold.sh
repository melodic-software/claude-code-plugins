#!/usr/bin/env bash
# Seeds a git repository with a remote, so the state-key resolver has a
# repository identity to print for this checkout.
set -euo pipefail

git init -q -b main
git config user.name dev
git config user.email dev@example.invalid
git remote add origin https://example.invalid/acme/orchard-map.git

cat >CLAUDE.md <<'MD'
# Orchard map

Field app for mapping fruit trees.

- Build: `make`
- Test: `make test`
MD

git add -A
git commit -q -m "chore: initial commit"
