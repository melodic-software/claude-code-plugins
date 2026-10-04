#!/usr/bin/env bash
# A small invoicing tool whose one module, tax, is already deep: compute_tax(order) is the only
# entry point, the rate tables, exemptions and rounding sit behind it, and the tests drive only it.
set -euo pipefail

git init -q -b main
git config user.name eval
git config user.email eval@example.invalid
mkdir -p tax tests docs/adr
: > tests/__init__.py

cat > tax/__init__.py <<'PY'
"""Sales tax for an order. compute_tax is the whole public interface."""
from tax._engine import TaxResult, compute_tax

__all__ = ["TaxResult", "compute_tax"]
PY

cat > tax/_engine.py <<'PY'
from dataclasses import dataclass
from decimal import Decimal

from tax._rates import exempt, rate_for
from tax._rounding import round_line


@dataclass(frozen=True)
class TaxResult:
    lines: tuple
    total_tax: Decimal
    total: Decimal


def compute_tax(order):
    """Tax every line of an order for its ship-to region and return per-line and total tax."""
    region = order["ship_to"]["region"]
    lines = []
    subtotal = Decimal("0")
    total_tax = Decimal("0")
    for line in order["lines"]:
        amount = Decimal(str(line["unit_price"])) * line["quantity"]
        amount -= Decimal(str(line.get("discount", 0)))
        if amount < 0:
            amount = Decimal("0")
        if exempt(line["category"], region, order.get("customer_type", "retail")):
            tax = Decimal("0")
        else:
            tax = round_line(amount * rate_for(line["category"], region), region)
        lines.append((line["sku"], amount, tax))
        subtotal += amount
        total_tax += tax
    return TaxResult(tuple(lines), total_tax, subtotal + total_tax)
PY

cat > tax/_rates.py <<'PY'
from decimal import Decimal

_BASE = {
    "WA": Decimal("0.065"),
    "OR": Decimal("0"),
    "CA": Decimal("0.0725"),
    "NY": Decimal("0.04"),
    "TX": Decimal("0.0625"),
}

_CATEGORY_OVERRIDES = {
    ("CA", "groceries"): Decimal("0"),
    ("NY", "clothing"): Decimal("0"),
    ("TX", "groceries"): Decimal("0"),
    ("WA", "digital"): Decimal("0.065"),
    ("NY", "digital"): Decimal("0.04"),
}

_EXEMPT_CUSTOMERS = {"nonprofit", "government"}


def rate_for(category, region):
    if region not in _BASE:
        raise ValueError("no tax table for region %s" % region)
    return _CATEGORY_OVERRIDES.get((region, category), _BASE[region])


def exempt(category, region, customer_type):
    if customer_type in _EXEMPT_CUSTOMERS:
        return True
    return category == "resale" and region != "OR"
PY

cat > tax/_rounding.py <<'PY'
from decimal import ROUND_HALF_EVEN, ROUND_HALF_UP, Decimal

_CENT = Decimal("0.01")
_BANKERS = {"NY"}


def round_line(value, region):
    mode = ROUND_HALF_EVEN if region in _BANKERS else ROUND_HALF_UP
    return value.quantize(_CENT, rounding=mode)
PY

cat > invoice.py <<'PY'
import json
import sys

from tax import compute_tax


def main(path):
    with open(path) as handle:
        order = json.load(handle)
    result = compute_tax(order)
    for sku, amount, tax in result.lines:
        print("%-10s %10s %8s" % (sku, amount, tax))
    print("tax %s  total %s" % (result.total_tax, result.total))


if __name__ == "__main__":
    main(sys.argv[1])
PY

cat > tests/test_tax.py <<'PY'
import unittest
from decimal import Decimal

from tax import compute_tax


def order(region, *lines, customer_type="retail"):
    return {"ship_to": {"region": region}, "customer_type": customer_type, "lines": list(lines)}


def line(sku, price, qty, category="general", discount=0):
    return {"sku": sku, "unit_price": price, "quantity": qty, "category": category, "discount": discount}


class ComputeTax(unittest.TestCase):
    def test_washington_general_goods(self):
        self.assertEqual(compute_tax(order("WA", line("A", 10, 2))).total_tax, Decimal("1.30"))

    def test_oregon_has_no_sales_tax(self):
        self.assertEqual(compute_tax(order("OR", line("A", 99.99, 1))).total_tax, Decimal("0"))

    def test_california_groceries_are_zero_rated(self):
        self.assertEqual(compute_tax(order("CA", line("G", 5, 4, "groceries"))).total_tax, Decimal("0"))

    def test_nonprofit_is_exempt(self):
        result = compute_tax(order("TX", line("A", 100, 1), customer_type="nonprofit"))
        self.assertEqual(result.total, Decimal("100"))

    def test_new_york_rounds_half_even(self):
        self.assertEqual(compute_tax(order("NY", line("A", "0.625", 1))).total_tax, Decimal("0.02"))

    def test_discount_never_goes_negative(self):
        result = compute_tax(order("WA", line("A", 5, 1, discount=10)))
        self.assertEqual(result.total, Decimal("0"))

    def test_unknown_region_is_rejected(self):
        with self.assertRaises(ValueError):
            compute_tax(order("ZZ", line("A", 1, 1)))


if __name__ == "__main__":
    unittest.main()
PY

cat > docs/adr/0001-keep-tax-rules-in-process.md <<'MD'
# 1. Keep tax rules in process

Status: accepted

The rate tables change a few times a year and ship with a release. They stay in the `tax` package
behind `compute_tax`; no rules service.
MD

cat > README.md <<'MD'
# invoice

`python3 invoice.py order.json` prints per-line tax and the order total. Tests: `python3 -m unittest`.
MD

git add .
git commit -q -m "feat: invoice tax calculation"
