#!/usr/bin/env bash
# A service with a nightly CSV export, about to be replaced by an event stream: the first decision
# opens later ones (broker, schema, cutover), so later rounds are known when round 1 is asked.
set -euo pipefail

git init -q -b main
git config user.name eval
git config user.email eval@example.invalid
mkdir -p export

cat >export/nightly.py <<'PY'
"""Writes every order changed today to warehouse/orders-YYYYMMDD.csv at 02:00."""
import csv


def run(orders, path):
    with open(path, "w", newline="") as handle:
        writer = csv.writer(handle)
        for order in orders:
            writer.writerow([order["id"], order["status"], order["total"]])
PY

cat >README.md <<'MD'
# orders-export

Nightly CSV export of changed orders to the warehouse team.
MD

git add .
git commit -q -m "feat: nightly export"
