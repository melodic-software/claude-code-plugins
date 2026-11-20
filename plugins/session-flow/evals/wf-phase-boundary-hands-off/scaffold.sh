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

## Phase 1: filter totals by currency [DONE]
## Phase 2: currency on every report helper [DONE] (merged)
## Phase 3: currency in the CSV export (src/export.py) [NOT STARTED]
EOF
cat >src/report.py <<'EOF'
def total(rows, currency="USD"):
    return sum(row["amount"] for row in rows if row.get("currency", "USD") == currency)
EOF
git add .gitignore PLAN.md src
git commit -q -m "currency on every report helper"
