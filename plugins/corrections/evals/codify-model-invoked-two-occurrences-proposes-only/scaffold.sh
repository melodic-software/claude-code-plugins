#!/usr/bin/env bash
set -euo pipefail
here="$(dirname "${BASH_SOURCE[0]}")"
bash "$here/../fixtures/repo.sh"
mkdir -p src/endpoints
printf 'export const requireAuth = (req: { user?: string }) => { if (!req.user) throw new Error("401"); };\n' >src/auth.ts
printf 'export const orders = (req: { user?: string }) => [];\n' >src/endpoints/orders.ts
git add . && git commit -q -m "feat: add the orders endpoint"
printf 'import { requireAuth } from "../auth";\nexport const orders = (req: { user?: string }) => { requireAuth(req); return []; };\n' >src/endpoints/orders.ts
git add . && git commit -q -m "fix: the orders endpoint skipped the shared auth helper"
printf 'export const invoices = (req: { user?: string }) => [];\n' >src/endpoints/invoices.ts
git add . && git commit -q -m "feat: add the invoices endpoint"
printf 'import { requireAuth } from "../auth";\nexport const invoices = (req: { user?: string }) => { requireAuth(req); return []; };\n' >src/endpoints/invoices.ts
git add . && git commit -q -m "fix: the invoices endpoint skipped the shared auth helper"
