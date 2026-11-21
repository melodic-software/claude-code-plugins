#!/usr/bin/env bash
set -euo pipefail

mkdir -p .work/invoice-export
cat >.work/invoice-export/interview-checklist.md <<'MD'
# /planning:interview Checklist

## Open-question register

- Q1 | answered | round 1 | What problem does this solve? | finance rebuilds the month's invoices by hand for reconciliation
- Q2 | answered | round 1 | Who uses it? | the finance team
- gap | Q3-Q599 | ids skipped by an earlier session
- Q600 | answered | round 1 | What quality bar does this work meet? | production
MD
