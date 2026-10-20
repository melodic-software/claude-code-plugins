#!/usr/bin/env bash
# Seeds an invoice export job and a log that shows it timing out for large accounts.
set -euo pipefail

mkdir -p src/export logs
cat >src/export/invoices.py <<'PY'
def export_invoices(account, db, writer):
    rows = db.query("SELECT * FROM invoices WHERE account_id = %s", account.id)
    for row in rows:
        writer.write(row)
PY
cat >logs/export.log <<'LOG'
02:00:01 export start account=1042 invoices=812
02:00:04 export done account=1042
02:00:05 export start account=2210 invoices=14380
02:30:05 export TIMEOUT account=2210 after 1800s
02:30:06 export start account=3377 invoices=11902
03:00:06 export TIMEOUT account=3377 after 1800s
LOG
