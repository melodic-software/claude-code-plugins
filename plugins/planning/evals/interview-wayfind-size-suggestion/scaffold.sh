#!/usr/bin/env bash
# Seeds an interview ledger whose register holds 31 rows after round 6, all answered.
set -euo pipefail

ledger=.work/billing-consolidation/interview-checklist.md
mkdir -p "${ledger%/*}"
{
  cat <<'MD'
# /planning:interview Checklist

## Constraint ledger

- C1 | confirmed | the three billing services merge into one | user, round 1

## Open-question register

MD
  for n in $(seq 1 31); do
    printf -- '- Q%d | answered | round %d | Billing consolidation question %d | settled\n' "$n" "$((n % 6 + 1))" "$n"
  done
} >"$ledger"
