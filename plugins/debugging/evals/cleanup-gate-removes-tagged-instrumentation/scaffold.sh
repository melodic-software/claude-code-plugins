#!/usr/bin/env bash
# A Python repo where a price-lookup fix is applied but not committed, with tagged debug
# instrumentation still in two source files and a Phase 1 loop script beside them.
set -euo pipefail

git init -q -b main
git config user.name eval
git config user.email eval@example.invalid

cat > pricing.py <<'PY'
PRICES = {"A": 12.5, "B": 4.0}


def unit_price(sku):
    return PRICES[sku.lower()]
PY

cat > checkout.py <<'PY'
from pricing import unit_price


def order_total(lines):
    total = 0
    for sku, qty in lines:
        total += unit_price(sku) * qty
    return round(total, 2)
PY

cat > repro_checkout.py <<'PY'
# Phase 1 loop: exits 1 while the checkout bug reproduces, 0 once it is gone.
import sys

from checkout import order_total

try:
    total = order_total([("A", 2), ("B", 1)])
except Exception as exc:
    print("BUG: %r" % exc)
    sys.exit(1)
print("total=%s" % total)
sys.exit(0 if total == 29.0 else 1)
PY

git add .
git commit -q -m "feat: checkout totals"

cat > pricing.py <<'PY'
PRICES = {"A": 12.5, "B": 4.0}


def unit_price(sku):
    price = PRICES[sku]
    print("[DEBUG-a4f2] lookup", sku, price)
    return price
PY

cat > checkout.py <<'PY'
from pricing import unit_price


def order_total(lines):
    total = 0
    for sku, qty in lines:
        price = unit_price(sku)
        print(f"[DEBUG-a4f2] sku={sku} qty={qty} price={price}")
        total += price * qty
    print(f"[DEBUG-a4f2] total={total}")
    return round(total, 2)
PY

cat > test_checkout.py <<'PY'
import unittest

from checkout import order_total


class OrderTotalTest(unittest.TestCase):
    def test_uppercase_skus_are_priced(self):
        self.assertEqual(order_total([("A", 2), ("B", 1)]), 29.0)


if __name__ == "__main__":
    unittest.main()
PY
