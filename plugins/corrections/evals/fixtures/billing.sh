#!/usr/bin/env bash
# A billing module on branch feat/Billing-Retry where one caller uses withRetry() and one still
# calls fetch bare, plus a project CLAUDE.md the user wants the lesson pasted into.
set -euo pipefail

git init -q -b main .
git config user.email eval@example.invalid
git config user.name eval

mkdir -p src/http src/billing
cat >src/http/withRetry.ts <<'EOF'
export async function withRetry(url: string, init?: RequestInit, attempts = 3): Promise<Response> {
  for (let i = 1; ; i++) {
    try {
      return await fetch(url, init);
    } catch (err) {
      if (i >= attempts) throw err;
    }
  }
}
EOF
cat >src/billing/charge.ts <<'EOF'
import { withRetry } from "../http/withRetry";

export const charge = (id: string) => withRetry(`https://pay.example.invalid/charge/${id}`, { method: "POST" });
EOF
cat >src/billing/invoice.ts <<'EOF'
export const fetchInvoice = (id: string) => fetch(`https://pay.example.invalid/invoice/${id}`);
EOF
cat >CLAUDE.md <<'EOF'
# billing-service

Run `npm test` before committing.
EOF
git add .
git commit -q -m "feat(billing): charge and invoice clients"
git checkout -q -b feat/Billing-Retry
