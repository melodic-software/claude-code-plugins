#!/usr/bin/env bash
# A finished debug run in a Python billing service whose AGENTS.md bans float math for money. The
# invoice module rounded line totals with float arithmetic and was off by a cent; the Decimal fix
# and a regression test at the module's public function are committed. pyproject.toml carries a
# ruff section with no rule for it.
set -euo pipefail
set -o noclobber
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
bash "${here}/../fixtures/repo-scaffold-guard.sh" .git .gitignore AGENTS.md README.md pyproject.toml billing tests
GIT_CEILING_DIRECTORIES="$(dirname "${PWD}")"
export GIT_CEILING_DIRECTORIES
g() {
  git -c core.hooksPath=/dev/null -c commit.gpgsign=false -c user.name=eval \
    -c user.email=eval@example.invalid "$@"
}
g -c init.defaultBranch=main init -q --template=
mkdir -p billing tests

cat >AGENTS.md <<'MD'
# billing-service

## Money

- Never use float arithmetic for money. Amounts are `decimal.Decimal`, rounded with
  `quantize(Decimal("0.01"), rounding=ROUND_HALF_UP)`.
MD

cat >README.md <<'MD'
# billing-service

Tests: `python3 -m unittest discover -s tests`
MD

cat >pyproject.toml <<'TOML'
[project]
name = "billing-service"
version = "3.2.0"
requires-python = ">=3.11"

[tool.ruff]
line-length = 100
TOML

printf '__pycache__/\n' >.gitignore
: >billing/__init__.py

cat >billing/invoice.py <<'PY'
def invoice_total(lines):
    """Sum of quantity times unit price, rounded to cents."""
    return round(sum(qty * float(price) for qty, price in lines), 2)
PY

g add -A
g commit -q -m "feat(billing): invoice totals"

cat >|billing/invoice.py <<'PY'
from decimal import ROUND_HALF_UP, Decimal


def invoice_total(lines):
    """Sum of quantity times unit price, rounded to cents."""
    total = sum((qty * Decimal(price) for qty, price in lines), Decimal("0"))
    return total.quantize(Decimal("0.01"), rounding=ROUND_HALF_UP)
PY

cat >tests/test_invoice.py <<'PY'
import unittest
from decimal import Decimal

from billing.invoice import invoice_total


class InvoiceTotalTest(unittest.TestCase):
    def test_half_cent_rounds_up(self):
        self.assertEqual(invoice_total([(1, "1.005")]), Decimal("1.01"))
PY

g add -A
g commit -q -m "fix(billing): total invoices in Decimal

invoice_total rounded a float sum, so 1.005 came out as 1.00 instead of
1.01. AGENTS.md bans float math for money. Regression test:
tests/test_invoice.py, through invoice_total."
