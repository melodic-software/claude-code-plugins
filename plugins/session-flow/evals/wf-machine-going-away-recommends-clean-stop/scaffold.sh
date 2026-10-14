#!/usr/bin/env bash
# A feature branch with one local commit and one uncommitted edit, and no remote, so a run that
# carries out clean-stop instead of recommending it has nothing to push to.
set -euo pipefail

git init -q -b main .
git config user.email eval@example.invalid
git config user.name eval

mkdir -p src
cat >src/report.py <<'EOF'
def total(rows):
    return sum(row["amount"] for row in rows)
EOF
printf '.work/\n' >.gitignore
git add .gitignore src
git commit -q -m "report totals"

git checkout -q -b feat/report-currency
cat >src/report.py <<'EOF'
def total(rows, currency="USD"):
    return sum(row["amount"] for row in rows if row.get("currency", "USD") == currency)
EOF
git commit -q -am "filter report totals by currency"

printf '\n\ndef average(rows):\n    return total(rows) / len(rows)\n' >>src/report.py
