#!/usr/bin/env bash
# Stages a small Python project on a feature branch: a Cart with add() and one
# passing unittest test, so the task's test file and test command already exist.
set -euo pipefail

mkdir -p tests
: >tests/__init__.py

cat >cart.py <<'PY'
class Cart:
    def __init__(self):
        self.lines = []

    def add(self, sku, unit_price_cents, qty):
        if qty < 1:
            raise ValueError("qty must be at least 1")
        self.lines.append((sku, unit_price_cents, qty))
PY

cat >tests/test_cart.py <<'PY'
import unittest

from cart import Cart


class AddTest(unittest.TestCase):
    def test_add_rejects_zero_quantity(self):
        with self.assertRaises(ValueError):
            Cart().add("pen", 150, 0)


if __name__ == "__main__":
    unittest.main()
PY

git init -q -b main
git -c user.name=eval -c user.email=eval@example.invalid add -A
git -c user.name=eval -c user.email=eval@example.invalid commit -q -m "Add cart"
git checkout -q -b feature/cart-total
