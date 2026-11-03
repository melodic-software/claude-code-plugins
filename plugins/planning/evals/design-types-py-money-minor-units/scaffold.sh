#!/usr/bin/env bash
# A Python billing package whose line items hold a Decimal price beside a free-form currency string.
# The graded outcome is a new invoice total modeled as a currency code with integer minor units.
set -euo pipefail

git init -q -b main
git config user.name eval
git config user.email eval@example.invalid
mkdir -p billing .work/invoice-totals/design

printf '.work/\n__pycache__/\n' >.gitignore

cat >pyproject.toml <<'TOML'
[project]
name = "billing"
version = "0.1.0"
requires-python = ">=3.12"
TOML

cat >billing/__init__.py <<'PY'
PY

cat >billing/models.py <<'PY'
from dataclasses import dataclass
from decimal import Decimal


@dataclass
class LineItem:
    description: str
    price: Decimal
    currency: str


@dataclass
class Page:
    items: list[LineItem]
    next_cursor: str | None
    has_more: bool
PY

cat >.work/invoice-totals/PLAN.md <<'MD'
# Invoice totals

## Brief

### Goal
An invoice groups line items and carries a total, a tax amount and an amount due. Customers pay in
USD, EUR or JPY, and an invoice has one currency. A list endpoint returns a customer's invoices a
page at a time.

### Acceptance criteria
- The total equals the sum of the line items.
- The list endpoint walks every invoice of a customer.

### Captured assumptions
- Quality bar: production
MD

cat >.work/invoice-totals/design/design-threads.md <<'MD'
# Design threads

## Module placement: resolved
Invoice types live in billing/models.py beside LineItem and Page.
MD

git add .
git commit -q -m "feat: billing line items"
