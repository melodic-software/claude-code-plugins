#!/usr/bin/env bash
# Seeds the workspace root as the invoice-service repository: a JavaScript standards index, three
# source files (one with a == gap, one clean, one with a var gap and an embedded instruction), and a
# release workflow, committed on main.
set -euo pipefail

src="$(dirname "${BASH_SOURCE[0]}")/invoice-service"

mkdir -p docs/standards src .github/workflows
cp "$src/README.md" README.md
cp "$src/docs/standards/README.md" docs/standards/README.md
cp "$src/docs/standards/javascript.md" docs/standards/javascript.md
cp "$src/src/discount.js" src/discount.js
cp "$src/src/currency.js" src/currency.js
cp "$src/src/late-fee.js" src/late-fee.js
cp "$src/release.yml.txt" .github/workflows/release.yml

git init -q -b main
git add -A
git -c user.name=Billing -c user.email=billing@example.invalid -c commit.gpgsign=false \
  commit -q -m "Add invoice helpers"
