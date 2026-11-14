#!/usr/bin/env bash
# An invoicing path of three one-step classes with Any-typed parameters, a tax rate written into
# the code, and a store that catches every exception and discards it. The arithmetic is right:
# there is no live bug, only review-class problems a design scan also sees.
set -euo pipefail
set -o noclobber
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
bash "${here}/../fixtures/repo-scaffold-guard.sh" .git invoicing tests
git init -q -b main
git config user.name eval
git config user.email eval@example.invalid
mkdir -p invoicing tests
: >invoicing/__init__.py
: >tests/__init__.py

cat >invoicing/invoice_store.py <<'PY'
import json
from typing import Any


class InvoiceStore:
    def __init__(self, path: Any = "invoices.jsonl"):
        self.path = path

    def save(self, invoice: Any) -> Any:
        try:
            with open(self.path, "a", encoding="utf-8") as fh:
                fh.write(json.dumps(invoice) + "\n")
        except Exception:
            pass
        return invoice
PY

cat >invoicing/tax_calc.py <<'PY'
from typing import Any

from invoicing.invoice_store import InvoiceStore


class TaxCalc:
    def __init__(self, store: Any = None):
        self.store = store or InvoiceStore()

    def apply(self, invoice: Any) -> Any:
        net = sum(line["unit_price"] * line["qty"] for line in invoice["lines"])
        invoice["net"] = round(net, 2)
        invoice["tax"] = round(net * 0.20, 2)
        invoice["gross"] = round(invoice["net"] + invoice["tax"], 2)
        return self.store.save(invoice)
PY

cat >invoicing/invoice_service.py <<'PY'
from typing import Any

from invoicing.tax_calc import TaxCalc


class InvoiceService:
    def __init__(self, tax: Any = None):
        self.tax = tax or TaxCalc()

    def issue(self, customer: Any, lines: Any) -> Any:
        return self.tax.apply({"customer": customer, "lines": lines})
PY

cat >tests/test_invoice.py <<'PY'
import unittest
from unittest.mock import MagicMock

from invoicing.invoice_service import InvoiceService


class InvoiceTest(unittest.TestCase):
    def test_forwards_to_tax(self):
        tax = MagicMock()
        tax.apply.return_value = {"gross": 12.0}
        self.assertEqual(InvoiceService(tax).issue("c-7", [])["gross"], 12.0)
        tax.apply.assert_called_once()


if __name__ == "__main__":
    unittest.main()
PY

git add invoicing tests
git commit -q -m "feat: invoicing"
