---
description: "Convert a spreadsheet export into the ledger import format, checking the column set and the date parsing before writing anything. Use when: 'import this export', 'convert the ledger file', 'the finance export needs converting'. Not for reconciling balances, which the ledger tool owns."
argument-hint: "<path to export file>"
user-invocable: true
disable-model-invocation: false
metadata:
  workflow-stage: anytime
  summary: Convert a finance export into the ledger import format
---

## Purpose

Take one export file and produce one import file. Report what changed in the conversion, and refuse
rather than guess when a column is missing.

## Before converting

Read the header row and compare it against the expected column set. A missing column is a stop, not
a default: a ledger row with a silently defaulted amount is worse than no row.

## Dates

The export writes dates in the locale of whoever produced it. Parse against the declared locale in
the file's own header, never against the machine's. Where the header declares none, ask.

## Output

Write beside the input, never over it. Name the output for the input plus the target format, so two
conversions of the same export do not collide.
