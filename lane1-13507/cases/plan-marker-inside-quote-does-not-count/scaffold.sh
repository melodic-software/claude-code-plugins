#!/usr/bin/env bash
# Seeds the eval workspace with the small export job the issue's problem is about.
set -euo pipefail

mkdir -p exports
printf '%s\n' \
  'import time' \
  '' \
  'TIMEOUT_SECONDS = 300' \
  '' \
  '' \
  'def run_nightly(account, db):' \
  '    started = time.monotonic()' \
  '    rows = db.fetch_all(account.id)  # one query, every row in memory' \
  '    out = []' \
  '    for row in rows:' \
  '        if time.monotonic() - started > TIMEOUT_SECONDS:' \
  '            raise TimeoutError(account.id)' \
  '        out.append(row.to_csv())' \
  '    return "\n".join(out)' >exports/nightly.py
