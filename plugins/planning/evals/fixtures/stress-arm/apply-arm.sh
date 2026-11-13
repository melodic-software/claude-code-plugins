#!/usr/bin/env bash
# Run by each st-* case's scaffold, in the eval workspace: writes the arm's planning settings where
# /planning:plan resolves them, commits the seeded project, and pushes it to a local bare origin,
# since the verification level is read from origin's default branch.
set -euo pipefail

mkdir -p docs/conventions
cp "$(dirname "${BASH_SOURCE[0]}")/planning.yaml" docs/conventions/planning.yaml
git add .
git commit -q -m "chore: import project"
# Inside .git, so the bare origin never shows in the work tree.
git init -q --bare -b main .git/eval-origin.git
git remote add origin "$PWD/.git/eval-origin.git"
git push -q origin main
