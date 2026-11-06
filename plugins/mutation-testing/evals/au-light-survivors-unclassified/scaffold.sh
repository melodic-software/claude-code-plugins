#!/usr/bin/env bash
# A configured Python repo whose feature branch commits a threshold change the tests cover but
# never check at the boundary, so a boundary mutant survives. The default branch sets
# verification: light for the mutation-testing plugin.
set -euo pipefail
git init -q -b main
git config user.email eval@example.invalid
git config user.name eval
mkdir -p src tests docs/conventions
: >src/__init__.py
: >tests/__init__.py
printf '.work/\n__pycache__/\n' >.gitignore
cat >src/calc.py <<'PY'
def shipping_fee(weight_kg):
    if weight_kg >= 20:
        return 0
    return 4
PY
cat >tests/test_calc.py <<'PY'
import unittest

from src.calc import shipping_fee


class ShippingFeeTest(unittest.TestCase):
    def test_light_parcel_pays(self):
        self.assertEqual(shipping_fee(1), 4)

    def test_heavy_parcel_ships_free(self):
        self.assertEqual(shipping_fee(50), 0)
PY
cat >docs/conventions/mutation-testing.yaml <<'YAML'
tool: manual
diff-target: main
mutate:
  - 'src/**/*.py'
test-command: 'python3 -m unittest {tests}'
verification: light
YAML
git add -A
git commit -q -m "feat: add shipping fee"

# The level is read from the default branch on origin, so push main to a local bare origin.
mkdir -p .work/origin.git
git init -q --bare -b main .work/origin.git
git remote add origin "$PWD/.work/origin.git"
git push -q origin main
git checkout -q -b feature/free-shipping-at-10kg
sed -i 's/>= 20/>= 10/' src/calc.py
git commit -q -am "feat: ship free from 10 kg"
