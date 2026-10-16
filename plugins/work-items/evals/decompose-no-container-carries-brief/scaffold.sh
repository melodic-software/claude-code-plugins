#!/usr/bin/env bash
# A small service checkout bound to the offline local-markdown tracker, with one approved PLAN.md
# whose Brief states a Goal and two Constraints that appear nowhere in its two plan phases. The
# prompt approves plain items with no spec container, so each item body is the only place the
# Brief's why can reach the session that later works the item.
set -euo pipefail

git init -q -b main
git config user.name eval
git config user.email eval@example.invalid

printf '.work/\n' > .gitignore
printf '# refunds\n\nRefund records and reports.\n' > README.md
mkdir -p refunds
printf 'def list_refunds(month):\n    return []\n' > refunds/store.py
: > refunds/__init__.py
cat > .work-item-tracker.json <<'JSON'
{"schema_version": "1.0", "provider": "local-markdown", "config": {"lease_ttl_hours": 24, "storage_dir": ".work-items"}}
JSON
git add .
git commit -q -m "chore: scaffold refunds"
git checkout -q -b refund-export

mkdir -p .work/refund-export
cat > .work/refund-export/PLAN.md <<'MD'
# refund-export

Approval: approved by the maintainer in the planning session

## Brief

### TLDR
- A monthly refund export as a CSV download.

### Goal
Finance staff reconcile refunds against the bank statement each month without asking engineering for a database query.

### Constraints
- The nightly ledger job's schedule and output stay untouched.
- The export reads only from the reporting replica, never the primary database.

### Acceptance criteria
- A month's refunds download as one CSV with one row per refund.
- An empty month downloads a CSV holding only the header row.

### Captured assumptions
- Months are calendar months in UTC: revisit if finance closes on another boundary.

### Out-of-scope
- Exports for other record types.

### Deferred questions
- none

## Plan

### Phase 1: monthly refund query [TODO]

- `list_refunds(month)` returns every refund whose timestamp falls in the month.
- **Sanity Check:** a unit test with refunds on both month edges passes.

### Phase 2: CSV download [TODO]

- A download endpoint renders the month's refunds as CSV, header row first.
- **Sanity Check:** a test requesting an empty month gets only the header row.
MD
