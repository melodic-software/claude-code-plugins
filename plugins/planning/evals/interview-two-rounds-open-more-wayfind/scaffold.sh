#!/usr/bin/env bash
set -euo pipefail

topic=.work/billing-consolidation
mkdir -p "$topic"
{
  cat <<'MD'
# /planning:interview Checklist

Planning version: 5.19.0

## Steps

- [x] Step 1: Survey before you ask
- [x] Step 1.5: Auto-detect: routed to the Q&A loop
- [ ] Step 2: Drive the rounds loop

## Constraint ledger

- C1 | confirmed | the three billing services merge into one | user, round 1

## Open-question register

MD
  for n in $(seq 1 12); do
    printf -- '- Q%d | answered | round %d | Billing consolidation question %d | settled topic:: billing\n' "$n" "$(((n - 1) / 3 + 1))" "$n"
  done
  cat <<'MD'
- Q13 | answered | round 5 | Which service's customer ids survive the merge? | the invoicing service's ids topic:: customer ids
- Q14 | open | round 5 | Which tax rules apply when one customer was billed by two services? | topic:: tax rules
- Q15 | open | round 5 | Do credit notes issued by the retired services stay valid? | topic:: credit notes
- Q16 | open | round 5 | Which service's payment retry schedule does the merged service keep? | topic:: payment retries
- Q17 | answered | round 6 | Do invoices keep their current numbering after the merge? | yes, each keeps its number topic:: invoice numbering
- Q18 | open | round 6 | Who approves a refund that spans two retired services? | topic:: refunds
- Q19 | open | round 6 | How long are the retired services' records kept read-only? | topic:: record retention
- Q20 | open | round 6 | Which currency does a merged account bill in when its accounts differed? | topic:: currency
MD
} >"$topic/interview-checklist.md"

for n in 5 6; do
  printf 'Round %d\n\nThe round as it was shown.\n' "$n" >"$topic/round-$n.md"
done
