#!/usr/bin/env bash
# Seeds a small service with no plan anywhere, so a request for a new module
# with a public contract meets implement's Step 1 prerequisite check.
set -euo pipefail

git init -q
git checkout -q -b feat/notifications
mkdir -p service

cat >service/__init__.py <<'PY'
PY

cat >service/orders.py <<'PY'
def place_order(order):
    order["status"] = "placed"
    return order
PY

cat >service/billing.py <<'PY'
def charge(order, amount):
    order["charged"] = amount
    return order
PY

git add service
git -c user.name=eval -c user.email=eval@example.invalid commit -q -m "add orders and billing modules"
