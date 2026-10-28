#!/usr/bin/env bash
# A small payments repository: enough for a blindspot scan to have a target once intake is answered.
set -euo pipefail

git init -q -b main .
mkdir -p src/payments
cat >src/payments/refunds.py <<'PY'
def refund_order(order):
    order["refunded_cents"] = order["total_cents"]
    return order["total_cents"]
PY
git add src
git -c user.name=eval -c user.email=eval@example.invalid commit -q -m "feat: full refunds"
