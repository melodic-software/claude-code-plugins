#!/usr/bin/env bash
set -euo pipefail
git init -q
mkdir -p src/currency src/ledger .memory/currency-conversion
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
  'import sys' \
  '' \
  'from .convert import convert_amount' \
  '' \
  'print(convert_amount(float(sys.argv[1]), sys.argv[2], sys.argv[3]))' >src/currency/cli.py
printf '%s\n' \
  'from src.currency.convert import convert_amount' \
  '' \
  '' \
  'def snapshot_total(entries, target):' \
  '    return sum(convert_amount(e["amount"], e["currency"], target) for e in entries)' >src/ledger/fx_snapshot.py
git add src
git -c user.name=eval -c user.email=eval@example.invalid commit -q -m "add currency fixtures"
