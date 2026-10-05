#!/usr/bin/env bash
# Seeds the eval workspace with a git repository holding one commit, so the git root is the
# workspace and not the home directory.
set -euo pipefail

git init -q -b main
git config user.name eval
git config user.email eval@example.invalid
mkdir -p src
printf 'export const exportInvoices = () => [];\n' >src/invoices.ts
git add src
git commit -q -m "feat(invoices): add export"
