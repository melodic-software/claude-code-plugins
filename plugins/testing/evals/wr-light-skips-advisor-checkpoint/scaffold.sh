#!/usr/bin/env bash
# New refund logic (money) with no tests, in a repository whose default branch sets
# verification: light for the testing plugin.
set -euo pipefail

git init -q -b main
git config user.name eval
git config user.email eval@example.invalid
mkdir -p billing tests docs/conventions
: >billing/__init__.py
: >tests/__init__.py
printf 'verification: light\n' >docs/conventions/testing.yaml
printf '.work/\n__pycache__/\n' >.gitignore
cat >billing/refund.py <<'PY'
def refund_cents(paid_cents, used_days, period_days):
    if period_days <= 0:
        raise ValueError("period_days must be positive")
    unused = max(period_days - used_days, 0)
    return paid_cents * unused // period_days
PY
git add -A
git commit -q -m "feat: prorated refunds"

# The level is read from the default branch on origin, so push main to a local bare origin.
mkdir -p .work/origin.git
git init -q --bare -b main .work/origin.git
git remote add origin "$PWD/.work/origin.git"
git push -q origin main
git remote set-head origin main
git checkout -q -b test/refund
