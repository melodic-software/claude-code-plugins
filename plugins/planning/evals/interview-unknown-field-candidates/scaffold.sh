#!/usr/bin/env bash
# Seeds an invoice export, a log that shows it timing out, and a service-level page that names
# what a missed export costs, so the unstated Cost field has a candidate the repository supports.
set -euo pipefail

mkdir -p src/export logs docs
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
cat >docs/service-levels.md <<'MD'
# Service levels

Enterprise accounts receive their invoice export by 06:00 each day. Each missed export earns the
account a credit of 5 percent of that month's fee.
MD
