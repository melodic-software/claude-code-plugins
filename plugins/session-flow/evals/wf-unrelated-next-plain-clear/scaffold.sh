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
mkdir -p docs
cat >docs/issue-4489.md <<'EOF'
# test_token_refresh fails about one run in twenty

tests/test_auth.py::test_token_refresh asserts on a random draw, so it fails about 5% of runs.
Replace the random draw with a fixed token clock.
EOF
git add .gitignore src tests docs
git commit -q -m "report currency merged"
