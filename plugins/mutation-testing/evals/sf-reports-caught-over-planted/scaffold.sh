#!/usr/bin/env bash
set -euo pipefail
git init -q -b main
git config user.email eval@example.invalid
git config user.name eval
mkdir -p src tests docs/conventions
: >src/__init__.py
: >tests/__init__.py
printf '.work/\n__pycache__/\n' >.gitignore
cat >src/pricing.py <<'PY'
def shipping_fee(weight_kg):
    if weight_kg >= 20:
        return 0
    return 4


def apply_discount(total, code):
    if code == "SAVE10" and total >= 50:
        return round(total * 0.9, 2)
    return total


def parse_quantity(text):
    value = int(text.strip())
    if value < 1:
        raise ValueError("quantity must be at least 1")
    return value
PY
cat >tests/test_pricing.py <<'PY'
import unittest

from src.pricing import apply_discount, parse_quantity, shipping_fee


class PricingTest(unittest.TestCase):
    def test_light_parcel_pays(self):
        self.assertEqual(shipping_fee(1), 4)

    def test_discount_applies(self):
        self.assertEqual(apply_discount(100, "SAVE10"), 90.0)

    def test_parses_quantity(self):
        self.assertEqual(parse_quantity(" 3 "), 3)
PY
cat >docs/conventions/mutation-testing.yaml <<'YAML'
tool: manual
diff-target: main
mutate:
  - 'src/**/*.py'
test-command: 'python3 -m unittest {tests}'
YAML
git add -A
git commit -q -m "feat: add pricing"
git update-ref refs/remotes/origin/main "$(git rev-parse HEAD)"
git symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/main
