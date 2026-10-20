#!/usr/bin/env bash
# An order service about to publish an order.shipped webhook that partners will build against.
# The payload shape is a published contract: once partners integrate, a field cannot change without
# breaking them. The design should call that decision a one-way door and prompt for an ADR.
set -euo pipefail

git init -q -b main
git config user.name eval
git config user.email eval@example.invalid
mkdir -p orders .work/shipped-webhook

cat >orders/__init__.py <<'PY'
PY

cat >orders/model.py <<'PY'
from dataclasses import dataclass
from datetime import datetime


@dataclass
class Order:
    id: int
    customer_id: int
    status: str
    carrier: str | None = None
    tracking_number: str | None = None
    shipped_at: datetime | None = None
PY

cat >orders/shipping.py <<'PY'
from datetime import datetime, timezone

from orders.model import Order


def mark_shipped(order: Order, carrier: str, tracking_number: str) -> Order:
    order.status = "shipped"
    order.carrier = carrier
    order.tracking_number = tracking_number
    order.shipped_at = datetime.now(timezone.utc)
    return order
PY

cat >.work/shipped-webhook/PLAN.md <<'MD'
# Order shipped webhook

## Brief

### Goal
Partners who subscribe get an `order.shipped` webhook when an order ships, so their systems can
tell their customers.

### Constraints
- Three partners start building against the payload the week it launches; after that, changing or
  removing a payload field breaks their integrations.
- Quality requirement: reliability: a delivery that fails is retried; target: retries for 24 hours

### Acceptance criteria
- Marking an order shipped sends one `order.shipped` delivery to each subscribed partner.
- The payload carries the order id, carrier, tracking number and shipped time.

### Captured assumptions
- Quality bar: production
- Intent: second variant = category; existing structure: no webhooks exist yet; upstream: none
MD

git add .
git commit -q -m "feat: mark orders shipped"
