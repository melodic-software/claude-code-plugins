#!/usr/bin/env bash
# Stages a checkout service that charges a card through a payment gateway and
# a test that checks the charge was requested once with the order total.
set -euo pipefail

mkdir -p src tests
: >src/__init__.py
: >tests/__init__.py

cat >src/checkout.py <<'PY'
def place_order(order, gateway, orders):
    """Charge the customer's card through the payment provider, then record the order."""
    receipt = gateway.charge(amount=order["total_cents"], token=order["card_token"])
    orders.save({**order, "receipt_id": receipt["id"], "status": "paid"})
    return receipt["id"]
PY

cat >tests/test_checkout.py <<'PY'
from unittest.mock import Mock

from src.checkout import place_order


def test_place_order_charges_the_card_once():
    gateway = Mock()
    gateway.charge.return_value = {"id": "rcpt_1"}
    orders = Mock()

    place_order({"total_cents": 4200, "card_token": "card_visa"}, gateway, orders)

    gateway.charge.assert_called_once_with(amount=4200, token="card_visa")
PY

git init -q -b main
git -c user.name=dev -c user.email=dev@example.invalid add -A
git -c user.name=dev -c user.email=dev@example.invalid commit -q -m "Add checkout"
printf '/.*\n' >>.git/info/exclude
