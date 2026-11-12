#!/usr/bin/env bash
# A small ledger package whose CSV export takes no delimiter, and a draft plan to add one.
set -euo pipefail

mkdir -p .work/export-delimiter/design ledger tests
cat >README.md <<'EOF'
# ledger

Ledger rows and the CSV export finance opens in a spreadsheet.
EOF
: >ledger/__init__.py
cat >ledger/export.py <<'EOF'
"""Write ledger rows to CSV for the finance spreadsheet."""
import csv

HEADER = ["date", "account", "amount"]


def export_csv(rows, path):
    with open(path, "w", newline="", encoding="utf-8") as handle:
        writer = csv.writer(handle)
        writer.writerow(HEADER)
        for row in rows:
            writer.writerow([row["date"], row["account"], row["amount"]])
EOF
cat >tests/test_export.py <<'EOF'
import os
import tempfile
import unittest

from ledger.export import export_csv


class ExportTest(unittest.TestCase):
    def test_default_is_comma(self):
        path = os.path.join(tempfile.mkdtemp(), "out.csv")
        export_csv([{"date": "2026-03-01", "account": "4000", "amount": "12.50"}], path)
        with open(path, encoding="utf-8") as handle:
            self.assertEqual(handle.read().splitlines(), ["date,account,amount", "2026-03-01,4000,12.50"])


if __name__ == "__main__":
    unittest.main()
EOF
cat >.work/export-delimiter/PLAN.md <<'EOF'
# Export delimiter

## Brief

### Problem
Finance staff whose spreadsheet splits columns on semicolons open the ledger export and get every row in one column.

### Goal
`export_csv` takes an optional delimiter, so those staff get one value per column.

### Acceptance criteria
- AC1: `export_csv(rows, path)` with no delimiter writes the same file as today.
- AC2: `export_csv(rows, path, delimiter=";")` writes every row, header included, with semicolons between fields.
- AC3: A delimiter other than `,` or `;` raises `ValueError` before the file is opened.

### Out-of-scope
- Changing the column set or order.
- Spreadsheet (.xlsx) output.

### Captured assumptions
- The finance spreadsheet imports semicolon-separated files without a separator hint line: revisit if finance reports an import that puts every value in one column.

## Design

Early exit (tier C): One optional parameter on one existing function; no new types.

## Plan

### Behavior
- B1: With no delimiter the export is unchanged (AC1). Delivered by Phase 1.
- B2: A semicolon delimiter separates every field of every row (AC2). Delivered by Phase 1.
- B3: An unsupported delimiter is refused before any file is written (AC3). Delivered by Phase 1.

### Load-bearing assumptions

| Assumption | Source | Falsifying check | Response if false |
|---|---|---|---|
| Rows always carry date, account and amount keys | plan | Phase 1 Sanity Check runs the existing export case | Minor: proceed and note |

### Phase 1: Add a delimiter option [STATUS]
**Satisfies:** AC1, AC2, AC3
**Delivers:** B1, B2, B3

- In `ledger/export.py`, add `delimiter=","` to `export_csv` and pass it to `csv.writer(handle, delimiter=delimiter)`.
- In `tests/test_export.py`, add a case that writes two rows with `delimiter=";"` and reads the file back line by line.

**Sanity Check:** `python -m unittest discover -s tests` exits 0.

### Files affected
| File | Action |
|---|---|
| `ledger/export.py` | modify |
| `tests/test_export.py` | modify |
EOF
cat >.work/export-delimiter/design/design-resolution.md <<'EOF'
outcome: early-exit
tier: C
reason: One optional parameter on one existing function; no new types.
EOF
bash "$(dirname "${BASH_SOURCE[0]}")/../fixtures/plan-reviewer-cut/init-repo.sh" feat/export-delimiter
