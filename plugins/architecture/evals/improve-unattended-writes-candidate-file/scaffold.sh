#!/usr/bin/env bash
set -euo pipefail

git init -q -b main
git config user.name eval
git config user.email eval@example.invalid
mkdir -p orders admin

: > orders/__init__.py
: > admin/__init__.py

cat > orders/handler.py <<'PY'
from orders.validator import OrderValidator


class OrderHandler:
    def __init__(self, validator=None):
        self.validator = validator or OrderValidator()

    def handle(self, order):
        return self.validator.validate(order)
PY

cat > orders/validator.py <<'PY'
from orders.repo import OrderRepo


class OrderValidator:
    def __init__(self, repo=None):
        self.repo = repo or OrderRepo()

    def validate(self, order):
        return self.repo.save(order)
PY

cat > orders/repo.py <<'PY'
class OrderRepo:
    def __init__(self):
        self.rows = []

    def save(self, order):
        self.rows.append(order)
        return len(self.rows)
PY

cat > admin/routes.py <<'PY'
from orders.repo import OrderRepo


def export_customer_cards(request, repo=None):
    # Served at GET /admin/export-cards. Any caller reaches it: no session or role is read.
    repo = repo or OrderRepo()
    return [{"customer": row["customer"], "card_number": row["card_number"]} for row in repo.rows]
PY

git add .
git commit -q -m "feat: order intake and admin export"
