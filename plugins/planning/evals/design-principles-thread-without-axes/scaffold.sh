#!/usr/bin/env bash
# A shop computes loyalty points inline in checkout. The Brief asks for a pure internal module that
# owns the calculation. Nothing in it touches configurability, extension points, observability or
# testability, so only an unconditional design-defaults pass writes a Principles thread.
set -euo pipefail

git init -q -b main
git config user.name eval
git config user.email eval@example.invalid
mkdir -p shop .work/loyalty-points

cat >shop/__init__.py <<'PY'
PY

cat >shop/model.py <<'PY'
from dataclasses import dataclass
from decimal import Decimal


@dataclass(frozen=True)
class Line:
    sku: str
    quantity: int
    unit_price: Decimal
    category: str


@dataclass(frozen=True)
class Order:
    id: int
    customer_id: int
    lines: tuple[Line, ...]
    member_since_years: int
PY

cat >shop/checkout.py <<'PY'
from decimal import ROUND_DOWN, Decimal

from shop.model import Order


def complete(order: Order) -> dict:
    total = sum((line.unit_price * line.quantity for line in order.lines), Decimal("0"))
    points = int((total).quantize(Decimal("1"), rounding=ROUND_DOWN))
    for line in order.lines:
        if line.category == "gift-card":
            points -= int((line.unit_price * line.quantity).quantize(Decimal("1"), rounding=ROUND_DOWN))
    if order.member_since_years >= 5:
        points = points * 2
    return {"order_id": order.id, "total": str(total), "points": max(points, 0)}
PY

cat >.work/loyalty-points/PLAN.md <<'MD'
# Loyalty points calculation

## Brief

### Goal
Move the loyalty-points rules out of `shop/checkout.py` into one internal module that owns the
calculation, so checkout only asks for the points an order earns.

### Constraints
- Same results as today for every existing order: one point per whole currency unit spent, gift
  cards earn nothing, members of five or more years earn double, never below zero.
- Internal only: checkout is the one caller; nothing outside this repository reads the points.

### Acceptance criteria
- Checkout gets an order's points from the new module and no longer holds any points rule.
- Every rule above keeps its current result.

### Captured assumptions
- Quality bar: production
- Intent: second variant = none expected; existing structure: the rules sit inline in checkout.complete; upstream: none
MD

git add .
git commit -q -m "feat: loyalty points in checkout"
