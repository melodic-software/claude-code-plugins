#!/usr/bin/env bash
# A locked Brief for an invoice CSV export with one captured assumption (the reporting replica lags
# the primary by under five minutes) and a tier B early-exit design record. The plan should carry
# that assumption into its Load-bearing assumptions table.
set -euo pipefail

git init -q -b main
git config user.name eval
git config user.email eval@example.invalid
mkdir -p app/reports tests .work/invoice-export/design

cat >app/__init__.py <<'PY'
PY

cat >app/db.py <<'PY'
def replica_connection():
    """Read-only connection to the reporting replica."""
    raise NotImplementedError


def primary_connection():
    raise NotImplementedError
PY

cat >app/reports/__init__.py <<'PY'
PY

cat >app/reports/refunds.py <<'PY'
import csv

from app.db import replica_connection


def export_refunds(out, day):
    rows = replica_connection().execute(
        "SELECT id, amount, created_at FROM refunds WHERE day = ?", (day,)
    )
    writer = csv.writer(out)
    writer.writerow(["id", "amount", "created_at"])
    writer.writerows(rows)
PY

cat >tests/test_refunds.py <<'PY'
def test_placeholder():
    assert True
PY

cat >.work/invoice-export/design/design-resolution.md <<'MD'
---
outcome: early-exit
tier: B
reason: one new export function beside the existing refunds export, same module and pattern
---

Type sketch: `export_invoices(out, day) -> None`, writing `id, customer, total, issued_at` rows.
MD

cat >.work/invoice-export/PLAN.md <<'MD'
## Brief

### TLDR
- A daily invoice CSV export beside the refunds export.

### Problem
- Gap: finance rebuilds the daily invoice list by hand from the admin screen.
- Who: the two finance analysts, every working day.
- Evidence: finance team request (rated: stated by the user).

### Goal
A daily invoice CSV that finance downloads instead of rebuilding the list by hand.
- Intent (why, in the user's words): "finance stops copying invoices out of the admin screen"
- Vision (where this heads): every finance report comes from one export module
- When goals conflict, prefer: matching the refunds export over new formatting

### Work size
- Small: one function and its test.

### Constraints
- Read from the reporting replica, never the primary.

### Acceptance criteria
- `export_invoices(out, day)` writes a header row and one row per invoice issued that day.
- A unit test covers an empty day and a day with two invoices.

### Captured assumptions
- Quality bar: internal
- The reporting replica lags the primary by under five minutes: revisit if finance needs invoices issued in the last five minutes

### Out-of-scope
- Scheduling the export.

### Deferred questions
None.

## Plan
MD

git add .
git commit -q -m "feat: refunds export"
