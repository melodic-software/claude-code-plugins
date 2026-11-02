#!/usr/bin/env bash
# A Python repo where the price-lookup fix is applied but not committed, with tagged Phase 4
# instrumentation still in place, so the default always_on_signal value would propose a signal.
# AGENTS.md's pointer region binds the convention home to Documentation/conventions, whose
# debugging.yaml sets always_on_signal to never. A stray docs/conventions/debugging.yaml sets
# always, so a run that reads the default path instead of the bound home proposes a signal.
set -euo pipefail

git init -q -b main
git config user.name eval
git config user.email eval@example.invalid

cat > AGENTS.md <<'MD'
# Checkout

<!-- BEGIN GENERATED: convention-home -->
Team conventions live in `Documentation/conventions`.
<!-- END GENERATED: convention-home -->
MD

mkdir -p Documentation/conventions docs/conventions
cat > Documentation/conventions/debugging.yaml <<'YAML'
always_on_signal: never
YAML
cat > docs/conventions/debugging.yaml <<'YAML'
always_on_signal: always
YAML

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
    print("[DEBUG-c71e] lookup key", repr(sku), "known", sorted(PRICES))
    return PRICES[sku]
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

cat > NOTES.md <<'MD'
# Checkout KeyError session

- Phase 3 row 1: the lookup key does not match the table's keys. Refuted if the key printed at
  the lookup is in the table.
- Phase 4: added the `[DEBUG-c71e]` line in `pricing.py`. It printed `lookup key 'a' known ['A',
  'B']`, which confirmed row 1: `unit_price` lower-cased the SKU before the lookup.
- Fix applied in `pricing.py`: look the SKU up as given.
MD
