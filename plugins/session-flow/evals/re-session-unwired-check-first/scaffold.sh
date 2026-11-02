#!/usr/bin/env bash
# A billing module with a lint script that flags a bare fetch() in src/billing, a CI workflow and
# package.json that never run it, no pre-commit hook, and an invoice client that calls fetch bare.
set -euo pipefail

git init -q -b main .
git config user.email eval@example.invalid
git config user.name eval

mkdir -p src/http src/billing scripts .github/workflows
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
cat >scripts/check-bare-fetch.sh <<'EOF'
#!/usr/bin/env bash
# Fails when a file under src/billing calls fetch( directly instead of withRetry().
set -euo pipefail
if grep -rn --include='*.ts' '\bfetch(' src/billing; then
  echo "bare fetch() in src/billing: call withRetry() from src/http/withRetry.ts" >&2
  exit 1
fi
EOF
chmod +x scripts/check-bare-fetch.sh
cat >package.json <<'EOF'
{
  "name": "billing-service",
  "private": true,
  "scripts": {
    "test": "node --test"
  }
}
EOF
cat >.github/workflows/ci.yml <<'EOF'
name: ci
on: [push, pull_request]
jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - run: npm test
EOF
cat >CLAUDE.md <<'EOF'
# billing-service

Run `npm test` before committing.
EOF
git add .
git commit -q -m "feat(billing): charge and invoice clients"
