#!/usr/bin/env bash
# Stages a clean feature branch whose tests/billing folder holds two
# assertion-free tests beside one real check, with origin/HEAD pointing at main.
set -euo pipefail

mkdir -p billing tests/billing
: >billing/__init__.py
: >tests/__init__.py
: >tests/billing/__init__.py

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
git -c user.name=dev -c user.email=dev@example.invalid add -A
git -c user.name=dev -c user.email=dev@example.invalid commit -q -m "Add invoice"
git update-ref refs/remotes/origin/main HEAD
git symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/main
git checkout -q -b chore/billing-tests
printf '/.*\n' >>.git/info/exclude
