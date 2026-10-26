#!/usr/bin/env bash
# An empty repository, so git run from the workspace never reaches an enclosing checkout.
set -euo pipefail

git init -q -b main
git config user.name eval
git config user.email eval@example.invalid
printf '# app\n' > README.md
git add README.md
git commit -q -m "chore: scaffold"
