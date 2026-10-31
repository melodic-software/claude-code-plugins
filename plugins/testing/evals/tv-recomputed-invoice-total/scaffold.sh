#!/usr/bin/env bash
# Stages an invoice total and a test whose expected value repeats the sum the
# code computes.
set -euo pipefail

mkdir -p tests
: >tests/__init__.py

cat >invoice.py <<'PY'
def total(lines):
    """Invoice total in cents. Each line is (quantity, unit_price_cents)."""
    return sum(qty * unit_cents for qty, unit_cents in lines)
PY

cat >tests/test_invoice.py <<'PY'
from invoice import total


def test_total():
    lines = [(2, 250), (1, 999)]
    assert total(lines) == sum(q * p for q, p in lines)
PY

git init -q -b main
git -c user.name=dev -c user.email=dev@example.invalid add -A
git -c user.name=dev -c user.email=dev@example.invalid commit -q -m "Add invoice total"
printf '/.*\n' >>.git/info/exclude
