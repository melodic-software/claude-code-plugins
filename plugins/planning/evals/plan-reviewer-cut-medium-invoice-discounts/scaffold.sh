#!/usr/bin/env bash
# A billing package that stores a line discount it never applies, and a draft plan to apply and show it.
set -euo pipefail

mkdir -p .work/invoice-discounts/design billing tests
cat >README.md <<'EOF'
# billing

Invoices for the order desk. Money rounding lives in billing/money.py.
EOF
: >billing/__init__.py
cat >billing/models.py <<'EOF'
from dataclasses import dataclass, field
from decimal import Decimal


@dataclass
class LineItem:
    description: str
    quantity: int
    unit_price: Decimal
    # Recorded by the order form; invoices do not apply it yet.
    discount_pct: Decimal = Decimal("0")


@dataclass
class Invoice:
    number: str
    items: list = field(default_factory=list)
EOF
cat >billing/money.py <<'EOF'
from decimal import ROUND_HALF_UP, Decimal


def round_cents(amount):
    return Decimal(amount).quantize(Decimal("0.01"), rounding=ROUND_HALF_UP)
EOF
cat >billing/pricing.py <<'EOF'
from billing import money


def line_total(item):
    return money.round_cents(item.quantity * item.unit_price)
EOF
cat >billing/invoice.py <<'EOF'
from decimal import Decimal

from billing import money, pricing

TAX_RATE = Decimal("0.20")


def totals(invoice):
    subtotal = sum((pricing.line_total(item) for item in invoice.items), Decimal("0"))
    tax = money.round_cents(subtotal * TAX_RATE)
    return {"subtotal": subtotal, "tax": tax, "total": subtotal + tax}
EOF
cat >billing/render.py <<'EOF'
from billing import invoice as invoice_totals
from billing import pricing


def render_text(invoice):
    lines = ["Invoice " + invoice.number]
    for item in invoice.items:
        lines.append("%-30s %3d x %8s %10s" % (item.description, item.quantity, item.unit_price, pricing.line_total(item)))
    sums = invoice_totals.totals(invoice)
    lines.append("Subtotal %s  Tax %s  Total %s" % (sums["subtotal"], sums["tax"], sums["total"]))
    return "\n".join(lines)
EOF
cat >tests/test_pricing.py <<'EOF'
import unittest
from decimal import Decimal

from billing.models import LineItem
from billing.pricing import line_total


class LineTotalTest(unittest.TestCase):
    def test_quantity_times_price(self):
        self.assertEqual(line_total(LineItem("pens", 3, Decimal("10.00"))), Decimal("30.00"))


if __name__ == "__main__":
    unittest.main()
EOF
cat >.work/invoice-discounts/PLAN.md <<'EOF'
# Apply line discounts on invoices

## Brief

### Problem
Sales enters line discounts on the order form, which stores `discount_pct`, but invoices ignore it: customers are billed full price and sales writes credit notes by hand.

### Goal
Invoices charge the discounted price and show the discount.

### Acceptance criteria
- AC1: `line_total` applies `discount_pct`: 3 at 10.00 with 15 percent off totals 25.50.
- AC2: The invoice subtotal and tax use the discounted line totals.
- AC3: An item with `discount_pct` 0 totals as today.
- AC4: The text invoice shows each discounted line's percentage beside its total, as `-15%`.

### Out-of-scope
- Invoice-level discounts.
- Changes to the order form.

### Captured assumptions
- `discount_pct` is between 0 and 100: revisit if sales asks to record credit lines as discounts above 100.

## Design

Early exit (tier C): Uses the existing `discount_pct` field; no new types or fields.

## Plan

### Behavior
- B1: A discounted line totals at the discounted price; an undiscounted line totals as today (AC1, AC3). Delivered by Phase 1.
- B2: Invoice subtotal and tax follow the discounted lines (AC2). Delivered by Phase 2.
- B3: The invoice text shows each line's discount percentage (AC4). Delivered by Phase 2.

### Load-bearing assumptions

| Assumption | Source | Falsifying check | Response if false |
|---|---|---|---|
| Tax is computed on the subtotal, not per line | plan | Phase 2 Sanity Check | Moderate: flag and continue |

### Phase 1: Discount line totals [STATUS]
**Satisfies:** AC1, AC3
**Delivers:** B1

- In `billing/pricing.py`, compute `item.quantity * item.unit_price * (100 - item.discount_pct) / 100` and pass it through `money.round_cents`.
- In `tests/test_pricing.py`, add cases for 15 percent and 0 percent.

**Sanity Check:** `python -m unittest tests.test_pricing` exits 0.

### Phase 2: Carry discounted totals through the invoice [STATUS]
**Satisfies:** AC2, AC4
**Delivers:** B2, B3

- `billing/invoice.py` keeps summing `pricing.line_total`, which now returns the discounted amount.
- In a new `tests/test_invoice.py`, assert the subtotal and tax of an invoice with one discounted line.

**Sanity Check:** `python -m unittest discover -s tests` exits 0.

### Files affected
| File | Action |
|---|---|
| `billing/pricing.py` | modify |
| `tests/test_pricing.py` | modify |
| `tests/test_invoice.py` | create |
EOF
cat >.work/invoice-discounts/design/design-resolution.md <<'EOF'
outcome: early-exit
tier: C
reason: Uses the existing `discount_pct` field; no new types or fields.
EOF
bash "$(dirname "${BASH_SOURCE[0]}")/../fixtures/plan-reviewer-cut/init-repo.sh" feat/invoice-discounts
