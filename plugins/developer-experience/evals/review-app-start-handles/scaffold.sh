#!/usr/bin/env bash
set -euo pipefail
fixtures="$(dirname "${BASH_SOURCE[0]}")/../fixtures"
bash "$fixtures/seed.sh" brackenfold converged
for f in bfk/app.py bfk/server.py bfk/cli.py scripts/deploy.sh; do
  cp "$fixtures/brackenfold-app-start/$f.txt" "$f"
done
chmod +x scripts/deploy.sh
git add -A
git -c user.name=eval -c user.email=eval@example.invalid -c commit.gpgsign=false commit -q -m "Add bfk app start"
