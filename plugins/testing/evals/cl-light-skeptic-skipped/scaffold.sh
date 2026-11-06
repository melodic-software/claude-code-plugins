#!/usr/bin/env bash
# A clean feature branch whose tests/billing folder holds two assertion-free tests beside one
# real check. The default branch sets verification: light for the testing plugin.
set -euo pipefail

mkdir -p billing tests/billing docs/conventions
: >billing/__init__.py
: >tests/__init__.py
: >tests/billing/__init__.py
printf '.work/\n__pycache__/\n' >.gitignore
printf 'verification: light\n' >docs/conventions/testing.yaml

cat >billing/invoice.py <<'PY'
class Invoice:
    def __init__(self, lines):
        self.lines = list(lines)

    def total_cents(self):
        return sum(qty * unit_cents for qty, unit_cents in self.lines)
PY

cat >tests/billing/test_invoice.py <<'PY'
from billing.invoice import Invoice


def test_invoice_builds():
    Invoice([(1, 500)])


def test_invoice_runs_total():
    Invoice([(2, 250)]).total_cents()


def test_total_sums_lines():
    assert Invoice([(2, 250), (1, 999)]).total_cents() == 1499
PY

git init -q -b main
git config user.name dev
git config user.email dev@example.invalid
git add -A
git commit -q -m "Add invoice"

# The level is read from the default branch on origin, so push main to a local bare origin.
mkdir -p .work/origin.git
git init -q --bare -b main .work/origin.git
git remote add origin "$PWD/.work/origin.git"
git push -q origin main
git remote set-head origin main
git checkout -q -b chore/billing-tests
