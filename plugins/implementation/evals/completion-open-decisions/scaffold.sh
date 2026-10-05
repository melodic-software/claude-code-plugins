#!/usr/bin/env bash
# Seeds a sandbox repository with an approved plan that leaves the interest
# rounding rule and compounding unsaid.
set -euo pipefail

git init -q
git checkout -q -b feat/late-interest
mkdir -p billing tests .work/late-interest

: >billing/__init__.py

cat >billing/interest.py <<'PY'
def late_interest_cents(balance_cents, months_overdue):
    return 0
PY

cat >tests/test_interest.py <<'PY'
import unittest

from billing.interest import late_interest_cents


class NotOverdue(unittest.TestCase):
    def test_no_interest_when_current(self):
        self.assertEqual(late_interest_cents(10000, 0), 0)


if __name__ == "__main__":
    unittest.main()
PY

cat >.gitignore <<'TXT'
.work/
TXT

cat >.work/late-interest/PLAN.md <<'MD'
# Late interest

## Brief

Goal: overdue invoices accrue late interest of 1.5% per month overdue.

## Plan

### Phase 1: interest rule [TODO]

- [ ] `billing/interest.py`: `late_interest_cents(balance_cents, months_overdue)` returns the
      interest owed in whole cents; `0` when `months_overdue` is `0` or less.
- [ ] Tests in `tests/test_interest.py`.

Acceptance: `python3 -m unittest discover tests` passes.

Approval: user, in the eval prompt.
MD

git add .gitignore billing tests
git -c user.name=eval -c user.email=eval@example.invalid commit -q -m "add interest module stub"
