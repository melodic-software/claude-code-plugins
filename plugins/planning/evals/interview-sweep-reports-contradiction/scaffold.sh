#!/usr/bin/env bash
set -euo pipefail

mkdir -p .work/invoice-export
cat >.work/invoice-export/interview-checklist.md <<'MD'
# /planning:interview Checklist

## Constraint ledger

- C1 | confirmed | support staff never see payment details | user, round 1

## Open-question register

- Q1 | answered | round 1 | What problem does this solve? | finance rebuilds the month's invoices by hand for reconciliation
- Q2 | answered | round 1 | Who may export invoices? | only users with the finance role
- Q3 | answered | round 2 | Which date range does one export cover? | one calendar month
- Q4 | answered | round 2 | How are amounts written? | decimal amounts with a currency column
- Q5 | answered | round 2 | How does a customer get a copy of their invoices? | a support agent exports the file and emails it to the customer
- Q6 | answered | round 2 | How are large exports built? | in a background job, offered for download when ready
MD
