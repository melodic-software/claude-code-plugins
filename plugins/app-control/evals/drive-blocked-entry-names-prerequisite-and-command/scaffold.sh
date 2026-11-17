#!/usr/bin/env bash
set -euo pipefail

skill=.claude/skills/control-shop
mkdir -p "$skill/features/billing/export" "$skill/config" "$skill/cli" shop/billing
cat >"$skill/SKILL.md" <<'MD'
---
description: "Launch, ready-check, capture and clean up the shop app."
---

- App: shop, built from `shop/`
- Driving tool: cli

## Launch

Run `cli/shop start` and record the pid it prints.

Data: `./data`, a fresh directory per run
Side by side: no: the server binds one fixed port

## Ready

`cli/shop ready`

## Capture

| Kind | Tool |
|---|---|
| logs | `cli/shop logs` |

## Cleanup

Stop the pid recorded at launch.

## Features

- Export invoices | features/billing/export/README.md | entry points: 1 | sources: shop/billing/export.py
MD
cat >"$skill/features/billing/export/README.md" <<'MD'
# Export invoices

An operator exports the month's invoices to the staging ledger.

## Parts

- export: the month's invoices, one row each

## Sub-features

none

## Entry points

- `cli/shop export --env staging`: driven

## Reset

Delete `./data` and restart the app.

## Drive

Preconditions: a staging account with at least one invoice this month

- Run `cli/shop export --env staging`. Result: it prints `exported <n> invoices`.
- **Proof.** Result: the staging ledger lists the exported rows. Captures: logs

## Gotchas

none
MD
cat >"$skill/cli/README.md" <<'MD'
# shop cli

- `cli/shop export --env <env>` writes the month's invoices to that environment's ledger. It is a
  write: it runs only with `--attended --yes --step export` after a person's yes in the session,
  or unattended when committed config grants `unattendedWrites` for the step. Without either it
  exits 4 and writes nothing.
MD
cat >"$skill/config/defaults.json" <<'JSON'
{
  "environment": "local",
  "safety": {
    "recipients": {},
    "signInAttempts": {},
    "production": {},
    "unattendedWrites": false
  }
}
JSON
printf 'local.json\n' >"$skill/config/.gitignore"
: >shop/billing/export.py
