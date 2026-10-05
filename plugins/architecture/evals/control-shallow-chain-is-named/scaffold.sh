#!/usr/bin/env bash
# Control for the no-findings cases: an order-intake path of three one-method pass-through classes,
# with the pricing and validation rules spread across them and tests that mock each hop. A correct
# scan names this chain as a candidate, so a skill that always answers "no candidates" fails here.
set -euo pipefail

git init -q -b main
git config user.name eval
git config user.email eval@example.invalid
mkdir -p orders tests
: > tests/__init__.py

cat > orders/__init__.py <<'PY'
PY

cat > orders/handler.py <<'PY'
from orders.validator import OrderValidator


class OrderHandler:
    def __init__(self, validator=None):
        self.validator = validator or OrderValidator()

    def handle(self, order):
        if order.get("coupon") == "WELCOME10":
            order["discount"] = 0.10
        return self.validator.validate(order)
PY

cat > orders/validator.py <<'PY'
from orders.repo import OrderRepo


class OrderValidator:
    def __init__(self, repo=None):
        self.repo = repo or OrderRepo()

    def validate(self, order):
        if not order.get("lines"):
            raise ValueError("order has no lines")
        order["subtotal"] = sum(l["price"] * l["qty"] for l in order["lines"])
        return self.repo.save(order)
PY

cat > orders/repo.py <<'PY'
class OrderRepo:
    def __init__(self):
        self.rows = []

    def save(self, order):
        order["total"] = round(order["subtotal"] * (1 - order.get("discount", 0)), 2)
        self.rows.append(order)
        return len(self.rows)
PY

cat > tests/test_handler.py <<'PY'
import unittest
from unittest.mock import MagicMock

from orders.handler import OrderHandler


class HandlerTest(unittest.TestCase):
    def test_forwards_to_validator(self):
        validator = MagicMock()
        validator.validate.return_value = 7
        self.assertEqual(OrderHandler(validator).handle({"lines": []}), 7)
        validator.validate.assert_called_once()


if __name__ == "__main__":
    unittest.main()
PY

cat > tests/test_validator.py <<'PY'
import unittest
from unittest.mock import MagicMock

from orders.validator import OrderValidator


class ValidatorTest(unittest.TestCase):
    def test_forwards_to_repo(self):
        repo = MagicMock()
        repo.save.return_value = 1
        self.assertEqual(OrderValidator(repo).validate({"lines": [{"price": 2, "qty": 1}]}), 1)
        repo.save.assert_called_once()


if __name__ == "__main__":
    unittest.main()
PY

git add .
git commit -q -m "feat: order intake"
