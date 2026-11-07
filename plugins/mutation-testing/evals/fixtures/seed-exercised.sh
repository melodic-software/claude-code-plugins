#!/usr/bin/env bash
# Seeds the exercised-scope repo: app.py (price_with_tax, lines 7-10 its body) and its config on
# main, plus one scenario's scenarios/<scenario>/test_app.py.
# Usage: seed-exercised.sh <no_assertion|boundary|calls_sut> <committed|uncommitted|on-main>
#   committed    the test is committed on branch feature/<scenario>-test
#   uncommitted  the test is left untracked on that branch
#   on-main      the test is committed on main, and the branch changes nothing
#
# Measured states per scenario (one mutant per line, python -m unittest):
#   M1 line 7 comparison inversion, M2-M4 lines 8-10 statement removal.
#   no_assertion: all four survive, cause no-assertion.
#   boundary: M2 survives (input-gap: no input above the threshold); M1, M3, M4 are killed.
#   calls_sut: all four survive, cause unclassified (the expected side calls price_with_tax).
set -euo pipefail
scenario="${1:?usage: seed-exercised.sh <scenario> <mode>}"
mode="${2:?usage: seed-exercised.sh <scenario> <mode>}"
git init -q -b main
git config user.email eval@example.invalid
git config user.name eval
mkdir -p scenarios docs/conventions
printf '.work/\n__pycache__/\n' >.gitignore
: >scenarios/__init__.py
cat >app.py <<'PY'
TAX_RATE = 0.2
DISCOUNT_THRESHOLD = 100
DISCOUNT_RATE = 0.1


def price_with_tax(amount):
    if amount > DISCOUNT_THRESHOLD:
        amount = amount * (1 - DISCOUNT_RATE)
    amount = amount * (1 + TAX_RATE)
    return round(amount, 2)
PY
cat >docs/conventions/mutation-testing.yaml <<'YAML'
tool: manual
diff-target: main
mutate:
  - app.py
operators: default
timeout-ms: 10000
baseline-suite-ms: 200
test-command: python -m unittest {tests}
YAML

write_test() {
  mkdir -p "scenarios/${scenario}"
  : >"scenarios/${scenario}/__init__.py"
  case "${scenario}" in
    no_assertion)
      cat >"scenarios/${scenario}/test_app.py" <<'PY'
import unittest

from app import price_with_tax


class PriceWithTaxTest(unittest.TestCase):
    def test_price_with_tax_runs(self):
        price_with_tax(150)


if __name__ == "__main__":
    unittest.main()
PY
      ;;
    boundary)
      cat >"scenarios/${scenario}/test_app.py" <<'PY'
import unittest

from app import price_with_tax


class PriceWithTaxTest(unittest.TestCase):
    def test_small_order_pays_tax_without_discount(self):
        # 50 is below the discount threshold; 50 plus 20% tax is 60.
        self.assertEqual(price_with_tax(50), 60.0)


if __name__ == "__main__":
    unittest.main()
PY
      ;;
    calls_sut)
      cat >"scenarios/${scenario}/test_app.py" <<'PY'
import unittest

from app import price_with_tax


class PriceWithTaxTest(unittest.TestCase):
    def test_price_with_tax_is_stable(self):
        expected = price_with_tax(150)
        self.assertEqual(price_with_tax(150), expected)


if __name__ == "__main__":
    unittest.main()
PY
      ;;
    *) echo "unknown scenario ${scenario}" >&2 && exit 2 ;;
  esac
}

[[ "${mode}" == on-main ]] && write_test
git add -A
git commit -q -m "feat: price with tax"
git update-ref refs/remotes/origin/main "$(git rev-parse HEAD)"
git symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/main
git checkout -q -b "feature/${scenario}-test"
case "${mode}" in
  committed)
    write_test
    git add -A
    git commit -q -m "test: ${scenario}"
    ;;
  uncommitted) write_test ;;
  on-main) ;;
  *) echo "unknown mode ${mode}" >&2 && exit 2 ;;
esac
