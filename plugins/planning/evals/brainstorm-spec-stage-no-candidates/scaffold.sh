#!/usr/bin/env bash
# Seeds a CSV exporter that builds the whole file in memory and a log of export timeouts.
set -euo pipefail

mkdir -p src/exports logs
cat >src/exports/csv_export.py <<'PY'
import csv
import io


def export_account(rows):
    buffer = io.StringIO()
    writer = csv.writer(buffer)
    for row in rows:
        writer.writerow(row)
    return buffer.getvalue()
PY
cat >logs/export-timeouts.log <<'LOG'
# week summary: 38 timeouts, 6 accounts, all over 50000 rows
09:14:02 timeout account=example-a rows=61200 elapsed=30s
11:40:51 timeout account=example-b rows=88410 elapsed=30s
LOG
