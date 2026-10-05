#!/usr/bin/env bash
# Seeds a sandbox repository with one rounding bug in two sibling functions.
set -euo pipefail

git init -q
git checkout -q -b fix/refund-rounding
mkdir -p payments tests

: >payments/__init__.py

cat >payments/refund.py <<'PY'
def refund_cents(paid_cents, fraction):
    return int(paid_cents * fraction)
PY

cat >payments/credit_note.py <<'PY'
def credit_cents(billed_cents, fraction):
    return int(billed_cents * fraction)
PY

cat >tests/test_whole_amounts.py <<'PY'
import unittest

from payments.credit_note import credit_cents
from payments.refund import refund_cents


class WholeAmounts(unittest.TestCase):
    def test_full_refund(self):
        self.assertEqual(refund_cents(1000, 1), 1000)

    def test_full_credit(self):
        self.assertEqual(credit_cents(1000, 1), 1000)


if __name__ == "__main__":
    unittest.main()
PY

git add payments tests
git -c user.name=eval -c user.email=eval@example.invalid commit -q -m "add refund and credit note amounts"
