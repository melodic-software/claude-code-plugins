#!/usr/bin/env bash
# A committed git repository with an API entrypoint directory and a billing directory, and no bugs
# config at any layer.
set -euo pipefail
set -o noclobber
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
bash "${here}/../fixtures/scaffold-guard.sh" .git .gitignore README.md docs src
git init -q
git config user.email eval@example.invalid
git config user.name eval
mkdir -p src/api src/billing
printf 'node_modules/\n' >.gitignore
printf '# Orders service\n\nHTTP handlers live in src/api/; invoicing and fees in src/billing/.\n' >README.md
printf 'export function listOrders() {\n  return [];\n}\n' >src/api/orders.ts
git add -A
git commit -q -m "feat(api): list orders"
printf 'export function getUser(id: string) {\n  return { id };\n}\n' >src/api/users.ts
printf 'export function invoiceTotal(lines: number[]) {\n  return lines.reduce((a, b) => a + b, 0);\n}\n' >src/billing/invoice.ts
git add -A
git commit -q -m "feat: users and invoices"
