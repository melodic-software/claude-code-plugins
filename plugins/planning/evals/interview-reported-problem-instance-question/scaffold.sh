#!/usr/bin/env bash
# Seeds an order-history CSV export that builds the whole file in memory, with no log or ticket
# behind the slowness, so the stated problem's only evidence is what support reported.
set -euo pipefail

mkdir -p src/export
cat >src/export/orders.py <<'PY'
import csv
import io


def export_orders(account, db):
    rows = db.query("SELECT * FROM orders WHERE account_id = %s", account.id)
    buffer = io.StringIO()
    writer = csv.writer(buffer)
    for row in rows:
        writer.writerow(row)
    return buffer.getvalue()
PY
