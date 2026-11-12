#!/usr/bin/env bash
# A shop package with a country-to-region map and flat shipping, and a draft plan for zone rates that builds its own map.
set -euo pipefail

mkdir -p .work/shipping-zones/design shop tests
cat >README.md <<'EOF'
# shop

Cart, checkout and shipping for the web shop. Country data lives in shop/geo.py.
EOF
: >shop/__init__.py
cat >shop/geo.py <<'EOF'
"""Country facts shared by checkout, tax and shipping."""
REGIONS = {"GB": "home", "IE": "eu", "FR": "eu", "DE": "eu", "ES": "eu", "US": "world", "CA": "world", "AU": "world"}


def country_region(code):
    """'home', 'eu' or 'world'; any code not listed is 'world'."""
    return REGIONS.get(code.upper(), "world")
EOF
cat >shop/settings.py <<'EOF'
from decimal import Decimal

FREE_SHIPPING_MIN = Decimal("50.00")
FLAT_RATE = Decimal("4.95")
EOF
cat >shop/shipping.py <<'EOF'
from decimal import Decimal

from shop import settings


def shipping_cost(cart_total):
    if cart_total >= settings.FREE_SHIPPING_MIN:
        return Decimal("0.00")
    return settings.FLAT_RATE
EOF
cat >shop/checkout.py <<'EOF'
from shop import geo, shipping


def checkout_summary(cart, country):
    total = sum(line["price"] * line["qty"] for line in cart)
    return {"region": geo.country_region(country), "items": total, "shipping": shipping.shipping_cost(total)}
EOF
cat >shop/views.py <<'EOF'
from shop.checkout import checkout_summary


def checkout_page(request):
    return checkout_summary(request["cart"], request["country"])
EOF
cat >tests/test_shipping.py <<'EOF'
import unittest
from decimal import Decimal

from shop.shipping import shipping_cost


class ShippingTest(unittest.TestCase):
    def test_flat_rate(self):
        self.assertEqual(shipping_cost(Decimal("10")), Decimal("4.95"))


if __name__ == "__main__":
    unittest.main()
EOF
cat >.work/shipping-zones/PLAN.md <<'EOF'
# Shipping by zone

## Brief

### Problem
Every order pays the domestic flat rate, so orders shipped abroad lose money on postage.

### Goal
Shipping cost depends on the destination's region.

### Acceptance criteria
- AC1: Region `home` keeps 4.95, free from a 50.00 cart.
- AC2: Region `eu` pays 9.95 and `world` pays 19.95; free shipping applies to `home` only.
- AC3: The checkout summary shows the rate for the destination country.
- AC4: A country code the shop does not know pays the `world` rate.

### Out-of-scope
- Carrier rate quotes.
- Weight-based pricing.

## Design

Early exit (tier C): Changes existing functions; no new types.

## Plan

### Behavior
- B1: Each destination pays its region's rate, unknown countries the world rate (AC2, AC4). Delivered by Phase 1 and Phase 2.
- B2: Domestic orders keep today's rate and free-shipping threshold (AC1). Delivered by Phase 2.
- B3: The checkout summary shows the destination's rate (AC3). Delivered by Phase 3.

### Load-bearing assumptions

| Assumption | Source | Falsifying check | Response if false |
|---|---|---|---|
| Country codes reach checkout as ISO 3166 alpha-2 | plan | Phase 3 Sanity Check | Moderate: flag and continue |

### Phase 1: Zone table [STATUS]
**Satisfies:** AC2, AC4
**Delivers:** B1

- Create `shop/data/zones.json` mapping each country code the shop ships to onto a zone (`home`, `eu`, `world`).
- Add `shop/zones.py` with `zone_for(country)`, which reads that file and returns `world` for a code it lacks.

**Sanity Check:** `python -c "from shop.zones import zone_for; assert zone_for('ZZ') == 'world'"` exits 0.

### Phase 2: Rate by zone [STATUS]
**Satisfies:** AC1, AC2
**Delivers:** B1, B2

- In `shop/shipping.py`, add a keyword argument, `shipping_cost(cart_total, country=None)`, where `None` keeps today's domestic rate: `home` 4.95 or free from `settings.FREE_SHIPPING_MIN`, `eu` 9.95, `world` 19.95.
- In `tests/test_shipping.py`, add one case per zone and one at the free-shipping threshold.

**Sanity Check:** checkout totals look correct for each zone.

### Phase 3: Show the rate at checkout [STATUS]
**Satisfies:** AC3
**Delivers:** B3

- In `shop/checkout.py`, pass `country`, which `checkout_summary` already receives, to `shipping_cost`.

**Sanity Check:** `python -m unittest discover -s tests` exits 0.

### Files affected
| File | Action |
|---|---|
| `shop/data/zones.json` | create |
| `shop/zones.py` | create |
| `shop/shipping.py` | modify |
| `shop/checkout.py` | modify |
| `tests/test_shipping.py` | modify |
EOF
cat >.work/shipping-zones/design/design-resolution.md <<'EOF'
outcome: early-exit
tier: C
reason: Changes existing functions; no new types.
EOF
bash "$(dirname "${BASH_SOURCE[0]}")/../fixtures/plan-reviewer-cut/init-repo.sh" feat/shipping-zones
