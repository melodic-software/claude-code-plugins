#!/usr/bin/env bash
set -euo pipefail

git init -q -b main
git config user.name eval
git config user.email eval@example.invalid
git remote add origin https://forge.example.invalid/harborline/hub.git

printf '# Harborline hub\n' > README.md
printf '*.log\n' > .gitignore
git add README.md .gitignore
git commit -q -m "seed the hub"

mkdir ledger-service
git -C ledger-service init -q -b main
printf '# Ledger service\n\nRun `make test` before every commit.\n' > ledger-service/AGENTS.md
git -C ledger-service add AGENTS.md
git -C ledger-service -c user.name=eval -c user.email=eval@example.invalid -c commit.gpgsign=false commit -q -m "seed the ledger service"
printf 'ledger-service/\n' >> .git/info/exclude
