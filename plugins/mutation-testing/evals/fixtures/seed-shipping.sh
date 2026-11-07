#!/usr/bin/env bash
# Seeds a Python repo whose feature branch commits a threshold change to src/calc.py that the tests
# cover but never check at the boundary. Usage: seed-shipping.sh <configured|unconfigured>.
# configured writes docs/conventions/mutation-testing.yaml (tool: manual, test-command set) on main.
set -euo pipefail
mode="${1:?usage: seed-shipping.sh <configured|unconfigured>}"
git init -q -b main
git config user.email eval@example.invalid
git config user.name eval
mkdir -p src tests
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
if [[ "${mode}" == configured ]]; then
  mkdir -p docs/conventions
  cat >docs/conventions/mutation-testing.yaml <<'YAML'
tool: manual
diff-target: main
mutate:
  - 'src/**/*.py'
test-command: 'python3 -m unittest {tests}'
YAML
fi
git add -A
git commit -q -m "feat: add shipping fee"
git update-ref refs/remotes/origin/main "$(git rev-parse HEAD)"
git symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/main
git checkout -q -b feature/free-shipping-at-10kg
sed -i 's/>= 20/>= 10/' src/calc.py
git commit -q -am "feat: ship free from 10 kg"
