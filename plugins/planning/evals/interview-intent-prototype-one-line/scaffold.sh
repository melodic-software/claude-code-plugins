#!/usr/bin/env bash
# A small reporting repository with a standards index. The prompt states a throwaway prototype that
# reads one external store, so the intent question collapses to one line and no quality
# requirement is asked: they are named as deferred.
set -euo pipefail

git init -q -b main
git config user.name eval
git config user.email eval@example.invalid
mkdir -p docs/standards src/reports

cat >docs/standards/README.md <<'MD'
---
standards-contract: 1.1.0
---

# Standards index

| Surface | Applies when | File |
|---|---|---|
| python | **/*.py; Python design or review tasks | python.md |
MD

cat >docs/standards/python.md <<'MD'
# Python

Target Python 3.12. Format with ruff. Each report is one module under `src/reports/`.
MD

cat >src/reports/__init__.py <<'PY'
PY

git add .
git commit -q -m "chore: reports package"

mkdir -p .work/orders-csv
cat >.work/orders-csv/interview-checklist.md <<'MD'
# /planning:interview Checklist

## Constraint ledger

- C1 | confirmed | a throwaway prototype that never ships; only the user runs it | user, round 1

## Open-question register

- Q1 | answered | round 1 | What must the report show finance? | last month's order count and revenue per day; kind:: discovery
- Q2 | answered | round 1 | Where do you start from? | nothing in this repository yet; a Shopify Admin API access token is in hand; kind:: discovery
MD
