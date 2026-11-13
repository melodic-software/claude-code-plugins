#!/usr/bin/env bash
# A clean checkout with nothing uncommitted, so the only state is what the tracker item holds.
set -euo pipefail

git init -q -b main .
git config user.email eval@example.invalid
git config user.name eval
printf '# booking\n' >README.md
git add README.md
git commit -q -m "chore: initial commit"
