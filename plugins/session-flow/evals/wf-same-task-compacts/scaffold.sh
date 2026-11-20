#!/usr/bin/env bash
set -euo pipefail

git init -q -b main .
git config user.email eval@example.invalid
git config user.name eval
git config commit.gpgsign false
printf '.work/\n' >.gitignore
mkdir -p src
cat >PLAN.md <<'EOF'
# Report currency

1. Filter totals by currency in src/report.py. [DONE]
2. Add currency to every report helper in src/report.py (total, average). [IN PROGRESS]
3. Document the currency argument in docs/report.md. [NOT STARTED]
EOF
cat >src/report.py <<'EOF'
def total(rows, currency="USD"):
    return sum(row["amount"] for row in rows if row.get("currency", "USD") == currency)
EOF
git add .gitignore PLAN.md src
git commit -q -m "filter report totals by currency"
