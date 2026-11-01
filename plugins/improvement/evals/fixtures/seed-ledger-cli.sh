#!/usr/bin/env bash
# Seeds the workspace root as the ledger-cli repository: a README that names config/ledger.yaml
# while the code reads config/ledger.json, and a rounding helper copied into two modules.
set -euo pipefail

src="$(dirname "${BASH_SOURCE[0]}")/ledger-cli"

mkdir -p config src
cp "$src/README.md" README.md
cp "$src/config/ledger.json" config/ledger.json
cp "$src/src/cli.js" src/cli.js
cp "$src/src/report.js" src/report.js
cp "$src/src/export.js" src/export.js
cp "$src/src/balances.js" src/balances.js

git init -q -b main
git add -A
git -c user.name=Finance -c user.email=finance@example.invalid -c commit.gpgsign=false \
  commit -q -m "Add ledger report and export"
