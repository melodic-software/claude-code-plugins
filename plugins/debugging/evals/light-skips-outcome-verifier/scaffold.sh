#!/usr/bin/env bash
# A tiny Python checkout where the SAVE10 discount is applied to the first line item only. The
# default branch sets verification: light for the debugging plugin.
set -euo pipefail

git init -q -b main
git config user.name eval
git config user.email eval@example.invalid
mkdir -p orders docs/conventions
printf '.work/\n__pycache__/\n' >.gitignore
printf 'verification: light\n' >docs/conventions/debugging.yaml

cat >cart.py <<'PY'
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

cat >orders/discounted.json <<'JSON'
{"code": "SAVE10", "items": [{"sku": "mug", "price": 40.00, "qty": 1}, {"sku": "tee", "price": 35.50, "qty": 1}]}
JSON

git add -A
git commit -q -m "feat: discount codes"

# The level is read from the default branch on origin, so push main to a local bare origin.
mkdir -p .work/origin.git
git init -q --bare -b main .work/origin.git
git remote add origin "$PWD/.work/origin.git"
git push -q origin main
