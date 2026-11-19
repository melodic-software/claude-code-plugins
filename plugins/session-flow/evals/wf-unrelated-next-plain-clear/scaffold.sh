#!/usr/bin/env bash
set -euo pipefail

git init -q -b main .
git config user.email eval@example.invalid
git config user.name eval
git config commit.gpgsign false
printf '.work/\n' >.gitignore
mkdir -p src tests
cat >src/report.py <<'EOF'
def total(rows, currency="USD"):
    return sum(row["amount"] for row in rows if row.get("currency", "USD") == currency)
EOF
cat >tests/test_auth.py <<'EOF'
import random


def test_token_refresh():
    assert random.random() < 0.95
EOF
git add .gitignore src tests
git commit -q -m "report currency merged"
