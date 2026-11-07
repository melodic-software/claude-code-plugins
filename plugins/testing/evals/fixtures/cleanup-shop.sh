#!/usr/bin/env bash
# Sourced by a cleanup scaffold after git-workspace.sh and ws_init. Defines:
#   shop_files   write the Python shop: shop/, shop_tests/ (a self-identical comparison, a weak
#                oracle on a trivial getter, a registry-reached handler with no assertion, a timing
#                test), REQUIREMENTS.md with worked prices, shop/total.sh, and the mutation-testing
#                config with test-command python -m unittest {tests}
#   shop_bash_test <dest>  write the hand-rolled bash harness that prints a total and checks nothing
unset GIT_DIR GIT_WORK_TREE GIT_CONFIG

shop_files() {
  mkdir -p shop shop_tests docs/conventions
  printf '.work/\n__pycache__/\n' >.gitignore
  : >shop_tests/__init__.py
  cat >shop/pricing.py <<'PY'
TAX_RATE = 0.2
DISCOUNT_THRESHOLD = 100
DISCOUNT_RATE = 0.1


def price_with_tax(amount):
    if amount > DISCOUNT_THRESHOLD:
        amount = amount * (1 - DISCOUNT_RATE)
    amount = amount * (1 + TAX_RATE)
    return round(amount, 2)


class Product:
    def __init__(self, name):
        self._name = name

    @property
    def name(self):
        return self._name
PY
  cat >shop/checkout.py <<'PY'
from shop.pricing import price_with_tax


def order_total(amounts):
    return round(sum(price_with_tax(a) for a in amounts), 2)
PY
  cat >shop/handlers.py <<'PY'
REGISTRY = {}


def register(name):
    def wrap(cls):
        REGISTRY[name] = cls
        return cls

    return wrap


@register("shipping")
class ShippingHandler:
    def fee(self, weight_kg):
        if weight_kg > 20:
            return 15
        return 5


def handle(kind, *args):
    return REGISTRY[kind]().fee(*args)
PY
  cat >shop/total.sh <<'SH'
#!/usr/bin/env bash
# order_total_cents <amount>: the amount plus 20% tax, in cents.
order_total_cents() {
  local cents=$(($1 * 100))
  echo $((cents * 12 / 10))
}
SH
  cat >shop_tests/test_pricing.py <<'PY'
import unittest

from shop.pricing import Product, price_with_tax


class PricingTest(unittest.TestCase):
    def test_price_is_consistent(self):
        self.assertEqual(price_with_tax(150), price_with_tax(150))

    def test_small_order_pays_tax_without_discount(self):
        # 50 is below the discount threshold; 50 plus 20% tax is 60.
        self.assertEqual(price_with_tax(50), 60.0)

    def test_product_name(self):
        self.assertIsNotNone(Product("lamp").name)


if __name__ == "__main__":
    unittest.main()
PY
  cat >shop_tests/test_receipt.py <<'PY'
import time
import unittest

from shop.checkout import order_total


class ReceiptTest(unittest.TestCase):
    def test_total_is_computed_quickly(self):
        start = time.monotonic()
        # 50 and 10 are below the threshold: 60 + 12 = 72.
        self.assertEqual(order_total([50, 10]), 72.0)
        self.assertLess(time.monotonic() - start, 1.0)


if __name__ == "__main__":
    unittest.main()
PY
  cat >shop_tests/test_handlers.py <<'PY'
import unittest

from shop.handlers import ShippingHandler


class ShippingHandlerTest(unittest.TestCase):
    def test_heavy_parcel_fee(self):
        ShippingHandler().fee(25)


if __name__ == "__main__":
    unittest.main()
PY
  cat >REQUIREMENTS.md <<'MD'
# Shop pricing requirements

1. Every price includes 20% sales tax.
2. An order line above 100 gets a 10% discount, applied before tax.
3. Prices are rounded to 2 decimal places.

Worked examples:

| Amount | Price |
|---|---|
| 50 | 60.00 |
| 150 | 162.00 |

Shipping fees are set per handler and are not specified here.
MD
  cat >docs/conventions/mutation-testing.yaml <<'YML'
tool: manual
command: none, the manual protocol applies each mutant by hand
diff-target: main
mutate:
  - shop/*.py
operators: default
timeout-ms: 10000
baseline-suite-ms: 300
test-command: python -m unittest {tests}
YML
}

shop_bash_test() {
  mkdir -p "$(dirname "${1:?dest}")"
  cat >"$1" <<'SH'
#!/usr/bin/env bash
# Hand-rolled harness: prints the total for one order and checks nothing.
set -uo pipefail
source "$(dirname "$0")/../shop/total.sh"
order_total_cents 50
SH
}
