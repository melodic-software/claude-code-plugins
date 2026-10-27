#!/usr/bin/env bash
# A small payments repository with three things a newcomer adding partial refunds would miss: a
# second caller that assumes a refund is always the whole order, a history commit explaining why
# amounts are integer cents, and a money helper every module routes through.
set -euo pipefail

export GIT_AUTHOR_NAME=eval GIT_AUTHOR_EMAIL=eval@example.invalid
export GIT_COMMITTER_NAME=eval GIT_COMMITTER_EMAIL=eval@example.invalid
export GIT_AUTHOR_DATE="2026-03-02T10:00:00Z" GIT_COMMITTER_DATE="2026-03-02T10:00:00Z"

git init -q -b main .
mkdir -p src/payments src/ledger tests

cat >src/payments/money.py <<'EOF'
def to_cents(amount_text):
    whole, _, frac = amount_text.partition(".")
    return int(whole) * 100 + int((frac + "00")[:2])
EOF

cat >src/payments/refunds.py <<'EOF'
from src.ledger.reconcile import mark_refunded


def refund_order(order):
    amount_cents = order["total_cents"]
    order["refunded_cents"] = amount_cents
    mark_refunded(order["id"])
    return amount_cents
EOF

cat >src/ledger/reconcile.py <<'EOF'
REFUNDED = set()


def mark_refunded(order_id):
    REFUNDED.add(order_id)


def open_balance(order):
    if order["id"] in REFUNDED:
        return 0
    return order["total_cents"]
EOF

cat >tests/test_refunds.py <<'EOF'
from src.payments.refunds import refund_order


def test_full_refund():
    order = {"id": "o1", "total_cents": 1250}
    assert refund_order(order) == 1250
EOF

git add src tests
git commit -q -m "feat: full refunds"

cat >>src/payments/money.py <<'EOF'


def from_cents(cents):
    return "%d.%02d" % divmod(cents, 100)
EOF
git add src/payments/money.py
GIT_AUTHOR_DATE="2026-04-14T09:30:00Z" GIT_COMMITTER_DATE="2026-04-14T09:30:00Z" \
  git commit -q -F - <<'EOF'
fix: keep every amount in integer cents

The acquirer rejected refunds sent as floats (0.1 + 0.2 drift) during the April incident.
All amounts stay integer cents end to end and go through money.py; never pass a float.
EOF
