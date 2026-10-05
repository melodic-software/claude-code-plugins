#!/usr/bin/env bash
# A tiny Python checkout where the SAVE10 discount is applied to the first line item only.
set -euo pipefail

git init -q -b main
git config user.name eval
git config user.email eval@example.invalid
mkdir -p orders

cat > cart.py <<'PY'
import json
import sys

DISCOUNTS = {"SAVE10": 0.10}


def total(order):
    rate = DISCOUNTS.get(order.get("code"), 0)
    amount = 0.0
    for index, item in enumerate(order["items"]):
        price = item["price"] * item["qty"]
        if index == 0:
            price *= 1 - rate
        amount += price
    return round(amount, 2)


if __name__ == "__main__":
    with open(sys.argv[1]) as handle:
        print("Total: %.2f" % total(json.load(handle)))
PY

cat > orders/discounted.json <<'JSON'
{"code": "SAVE10", "items": [{"sku": "mug", "price": 40.00, "qty": 1}, {"sku": "tee", "price": 35.50, "qty": 1}]}
JSON

git add .
git commit -q -m "feat: discount codes"
