#!/usr/bin/env bash
set -euo pipefail

mkdir -p .work/invoice-export
cat >.work/invoice-export/interview-checklist.md <<'MD'
# /planning:interview Checklist

Planning version: 5.19.0

## Steps

- [x] Step 1: Survey before you ask
- [x] Step 1.5: Auto-detect: routed to the Q&A loop
- [x] Step 2: Drive the rounds loop
- [x] Step 2 exit: Assumption sweep
- [ ] Step 3: Recognize the stop condition
- [ ] Step 4: Persist the Brief
- [ ] Step 5: Hand off

## Problems

- P1 | finance reconciles month-end invoices by hand because no export opens in their spreadsheet | agreed

## Constraint ledger

- C1 | confirmed | amounts are stored as integer cents with a currency code | user, round 1

## Open-question register

- Q1 | answered | round 1 | What problem should the invoice export solve? | finance reconciles month-end invoices by hand kind:: discovery problem:: P1 topic:: the problem
- Q2 | answered | round 1 | Which quality bar is this for? | production topic:: quality bar
- Q3 | answered | round 2 | Should one export cover one calendar month across all accounts? | yes, one calendar month topic:: date range
- Q4 | answered | round 2 | Should amounts be written as two-decimal numbers with a currency column? | yes, 1234.50 plus a currency column topic:: amount format
- Q5 | answered | round 2 | Should only the finance role be able to export? | hedged: probably, finance only topic:: who may export
- Q6 | answered | round 2 | Should the file be built in the background and offered once it is ready? | yes, built in the background topic:: how the file is built

## Terminology matrix

| Term | Definition | Source | Status |
|---|---|---|---|
| invoice | an issued invoice, drafts excluded | user, round 1 | agreed |

## Glossary lookup

- none found; searched docs/ and CONTEXT.md

## Assumption sweep

- sweep 1 | register through Q6
- none

## Captured assumptions

- the largest month stays under 100,000 rows; revisit if an account passes it

## ADR outcomes

- Q6 (background build) | declined: a two-way door
- every other decision | declined: no real alternative weighed
MD
