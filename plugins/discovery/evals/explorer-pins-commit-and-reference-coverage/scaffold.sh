#!/usr/bin/env bash
set -euo pipefail
git init -q
mkdir -p src/payments tests .memory/payments-rounding
printf '%s\n' \
  'from decimal import Decimal, ROUND_HALF_EVEN' \
  '' \
  '' \
  'def round_minor(amount):' \
  '    return Decimal(str(amount)).quantize(Decimal("0.01"), rounding=ROUND_HALF_EVEN)' >src/payments/rounding.py
printf '%s\n' \
  'from .rounding import round_minor' \
  '' \
  '' \
  'def charge_total(lines):' \
  '    return round_minor(sum(line["amount"] for line in lines))' >src/payments/charge.py
printf '%s\n' \
  'from src.payments.rounding import round_minor' \
  '' \
  '' \
  'def test_half_even():' \
  '    assert str(round_minor(0.125)) == "0.12"' >tests/test_rounding.py
git add src tests
# Fixed identity and dates make the commit sha the same on every run, so the
# grader can match the exact value a correct run must record.
GIT_AUTHOR_DATE='2026-01-01T00:00:00Z' GIT_COMMITTER_DATE='2026-01-01T00:00:00Z' \
  git -c user.name=eval -c user.email=eval@example.invalid -c commit.gpgsign=false \
  commit -q -m "add payments rounding fixtures"
