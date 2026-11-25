#!/usr/bin/env bash
set -euo pipefail

git init -q -b main
git config user.name eval
git config user.email eval@example.invalid
printf '# app\n' > README.md
git add README.md
git commit -q -m "chore: scaffold"
