#!/usr/bin/env bash
# An orders service with docs but no decision records, no ADR directory, and no declared
# place for them.
set -euo pipefail

git init -q -b main
git config user.name eval
git config user.email eval@example.invalid
mkdir -p src/orders docs

cat >src/orders/store.py <<'PY'
"""Persistence for orders."""


def save(order):
    raise NotImplementedError
PY

cat >docs/runbook.md <<'MD'
# Runbook

Restart the orders worker with `make restart-worker`.
MD

cat >README.md <<'MD'
# orders-service

Takes orders from the storefront and hands them to fulfillment.
MD

git add -A
git commit -q -m "Orders service skeleton"
