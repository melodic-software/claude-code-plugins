#!/usr/bin/env bash
# Seeds a git repository with a remote and a short CLAUDE.md, so the report
# action has a project to key on and nothing saved under that key.
set -euo pipefail

git init -q -b main
git config user.name dev
git config user.email dev@example.invalid
git remote add origin https://example.invalid/acme/greenhouse.git

cat >CLAUDE.md <<'MD'
# Greenhouse controller

Firmware and dashboard for the greenhouse sensors.

- Build: `make`
- Test: `make test`
MD

git add -A
git commit -q -m "chore: initial commit"
