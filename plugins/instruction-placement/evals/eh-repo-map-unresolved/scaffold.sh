#!/usr/bin/env bash
set -euo pipefail

git init -q -b main
git config user.name eval
git config user.email eval@example.invalid
git config commit.gpgsign false
git remote add origin https://forge.example.invalid/harborline/hub.git

printf '# Harborline hub\n' > README.md
printf '*.log\n' > .gitignore
git add README.md .gitignore
git commit -q -m "seed the hub"

for name in ledger-service portal-web; do
  mkdir "$name"
  git -C "$name" init -q -b main
  printf '# %s\n' "$name" > "$name/AGENTS.md"
  git -C "$name" add AGENTS.md
  git -C "$name" -c user.name=eval -c user.email=eval@example.invalid -c commit.gpgsign=false commit -q -m "seed"
  printf '%s/\n' "$name" >> .git/info/exclude
done
