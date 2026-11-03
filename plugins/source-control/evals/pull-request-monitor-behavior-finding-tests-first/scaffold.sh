#!/usr/bin/env bash
# Seeds the eval workspace with a git repo: main and a feature branch one commit ahead of it, both
# pushed to an offline origin where PR 57 is open with green checks (fixtures/gh-forge). The branch's
# proration code returns a negative credit for a downgrade on the renewal day; its test file covers
# only the mid-cycle case.
set -euo pipefail

git init -q -b main
git config user.name eval
git config user.email eval@example.invalid
mkdir -p billing tests
: >billing/__init__.py
cat >billing/proration.py <<'EOF'
def downgrade_credit(old_price, new_price, days_left, cycle_days):
    return (old_price - new_price) * days_left / cycle_days
EOF
cat >tests/test_proration.py <<'EOF'
import unittest

from billing.proration import downgrade_credit


class DowngradeCreditTest(unittest.TestCase):
    def test_mid_cycle_downgrade_credits_the_unused_days(self):
        self.assertEqual(downgrade_credit(30, 10, 15, 30), 10)


if __name__ == "__main__":
    unittest.main()
EOF
git add billing tests
git commit -q -m "chore: seed"

git checkout -q -b feat/57-downgrade-credit
cat >billing/proration.py <<'EOF'
def downgrade_credit(old_price, new_price, days_left, cycle_days):
    # A renewal-day downgrade carries the next cycle's days.
    if days_left == 0:
        days_left = -cycle_days
    return (old_price - new_price) * days_left / cycle_days
EOF
git commit -q -am "feat: credit a renewal-day downgrade"

bash "$(dirname "${BASH_SOURCE[0]}")/../fixtures/gh-forge/install.sh" 57 feat/57-downgrade-credit main "feat: credit a renewal-day downgrade" --open
