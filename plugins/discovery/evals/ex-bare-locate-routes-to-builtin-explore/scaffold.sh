#!/usr/bin/env bash
# A small currency package: convert_amount is defined in one file and called from two others.
set -euo pipefail

git init -q -b main .
mkdir -p src/currency src/ledger
printf '%s\n' \
  'from .rates import rate_for' \
  '' \
  '' \
  'def convert_amount(amount, source, target):' \
  '    return round(amount * rate_for(source, target), 2)' >src/currency/convert.py
printf '%s\n' \
  'RATES = {("USD", "EUR"): 0.92, ("EUR", "USD"): 1.09}' \
  '' \
  '' \
  'def rate_for(source, target):' \
  '    return 1.0 if source == target else RATES[(source, target)]' >src/currency/rates.py
printf '%s\n' \
  'from src.currency.convert import convert_amount' \
  '' \
  '' \
  'def snapshot_total(entries, target):' \
  '    return sum(convert_amount(e["amount"], e["currency"], target) for e in entries)' >src/ledger/fx_snapshot.py
git add src
git -c user.name=eval -c user.email=eval@example.invalid commit -q -m "add currency fixtures"
