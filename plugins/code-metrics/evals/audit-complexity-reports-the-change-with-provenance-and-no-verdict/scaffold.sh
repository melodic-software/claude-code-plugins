#!/usr/bin/env bash
set -euo pipefail
git init -q
git symbolic-ref HEAD refs/heads/main
printf '%s\n' 'def total(prices):' '    return sum(prices)' >billing.py
git add billing.py
git -c user.name=eval -c user.email=eval@example.invalid commit -q -m "add fixtures"
printf '%s\n' \
  '' \
  'def discount(customer, total, coupon=None):' \
  '    rate = 0' \
  '    if customer.get("member"):' \
  '        rate += 5' \
  '        if customer.get("years", 0) > 3:' \
  '            rate += 5' \
  '    if coupon:' \
  '        if coupon.startswith("VIP"):' \
  '            rate += 15' \
  '        elif coupon.startswith("SALE"):' \
  '            rate += 10' \
  '        else:' \
  '            rate += 2' \
  '    for item in customer.get("items", []):' \
  '        if item.get("clearance") and total > 100:' \
  '            rate += 1' \
  '    return total * (100 - min(rate, 40)) / 100' >>billing.py
