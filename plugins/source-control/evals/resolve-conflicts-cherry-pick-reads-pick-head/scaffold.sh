#!/usr/bin/env bash
# release/1.4 stopped cherry-picking main's late-fee cap: release named the rate LATE_RATE,
# the picked commit added MAX_LATE_FEE and a min() around the same return line.
set -euo pipefail

git init -q -b main
git config user.name eval
git config user.email eval@example.invalid
git config rerere.enabled false

mkdir -p billing
: > billing/__init__.py
cat > billing/rules.py <<'PY'
def late_fee(balance, days_late):
    if days_late <= 0:
        return 0
    return round(balance * 0.02, 2)
PY
cat > test_rules.py <<'PY'
import unittest

from billing.rules import late_fee


class LateFeeTest(unittest.TestCase):
    def test_two_percent(self):
        self.assertEqual(late_fee(100, 10), 2.0)


if __name__ == "__main__":
    unittest.main()
PY
git add .
git commit -q -m "feat(billing): late fees"

git checkout -q -b release/1.4
cat > billing/rules.py <<'PY'
LATE_RATE = 0.02


def late_fee(balance, days_late):
    if days_late <= 0:
        return 0
    return round(balance * LATE_RATE, 2)
PY
git add billing/rules.py
git commit -q -m "refactor(billing): name the late-fee rate" -m "Finance changes the rate each quarter; one named constant is the only place to edit. Refs BILL-190."

git checkout -q main
cat > billing/rules.py <<'PY'
MAX_LATE_FEE = 50


def late_fee(balance, days_late):
    if days_late <= 0:
        return 0
    return min(round(balance * 0.02, 2), MAX_LATE_FEE)
PY
cat > test_cap.py <<'PY'
import unittest

from billing.rules import late_fee


class CapTest(unittest.TestCase):
    def test_fee_is_capped(self):
        self.assertEqual(late_fee(10000, 10), 50)


if __name__ == "__main__":
    unittest.main()
PY
git add billing/rules.py test_cap.py
git commit -q -m "fix(billing): cap the late fee at 50" -m "Regulators cap late fees at 50 per invoice; uncapped fees on large balances were being refunded by hand. Refs BILL-203."
CAP=$(git rev-parse HEAD)
printf '# billing\n' > README.md
git add README.md
git commit -q -m "docs: billing readme"

git checkout -q release/1.4
git cherry-pick "$CAP" >/dev/null 2>&1 || true
test -f .git/CHERRY_PICK_HEAD
test ! -f .git/MERGE_HEAD
grep -qx billing/rules.py < <(git diff --name-only --diff-filter=U)
