#!/usr/bin/env bash
# Seeds a small coffee shop with one product sold as a one-off purchase and as a subscription, and
# no glossary, so "order" and "refund" are unsettled.
set -euo pipefail

mkdir -p src/shop
cat >src/shop/models.py <<'PY'
from dataclasses import dataclass
from datetime import date


@dataclass
class Purchase:
    customer: str
    product_sku: str
    amount_pence: int
    placed_on: date


@dataclass
class Subscription:
    customer: str
    product_sku: str
    amount_pence: int
    renews_on_day: int
PY
cat >README.md <<'MD'
# Roastery

Sells a 250 g coffee bag as a one-off purchase or as a monthly subscription.
MD
