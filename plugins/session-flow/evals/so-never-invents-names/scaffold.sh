#!/usr/bin/env bash
# A fresh repository with one commit and no memory root, so no upstream artifact exists yet.
set -euo pipefail

git init -q -b main
git config user.name eval
git config user.email eval@example.invalid
mkdir -p src
printf 'export const exportInvoices = () => [];\n' >src/invoices.ts
printf '.work/\n' >.gitignore
git add .gitignore src
git commit -q -m "feat(invoices): add export"
