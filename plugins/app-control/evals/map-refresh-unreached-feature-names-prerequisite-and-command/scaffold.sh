#!/usr/bin/env bash
set -euo pipefail

skill=.claude/skills/control-shop
out=out/billing.export
mkdir -p "$skill/features/billing/export" "$skill/cli" shop/billing "$out"
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

- `cli/shop export --env staging`: not driven: pending

## Reset

Delete `./data` and restart the app.

## Drive

Preconditions: a staging account with at least one invoice this month

- Run `cli/shop export --env staging`. Result: it prints `exported <n> invoices`.
- **Proof.** Result: the staging ledger lists the exported rows. Captures: logs

## Gotchas

- An empty month exports zero rows and still exits 0.
MD
printf '%s\n' '#!/usr/bin/env bash' 'echo "shop cli"' >"$skill/cli/shop"
: >shop/billing/export.py
cat >"$out/report.json" <<'JSON'
{
  "resolved": {"file": "features/billing/export/README.md", "part": null},
  "mode": "unattended",
  "steps": [
    {
      "action": "Run `cli/shop export --env staging`",
      "entry_point": "`cli/shop export --env staging`",
      "stated_result": "it prints `exported <n> invoices`",
      "observed": "refused before running: the step writes to staging",
      "artifacts": ["out/billing.export/export-refused.txt"],
      "command": null,
      "exit_code": null,
      "stderr": ""
    }
  ],
  "capability_gaps": [],
  "blocked": [
    {
      "reason": "blocked: the step writes to staging and this run holds no write grant for it",
      "prerequisite": "write grant for staging",
      "attempted": "cli/shop export --env staging",
      "grant": "write grant for staging"
    }
  ],
  "cleanup": {
    "stopped": ["cli/shop start (pid 7311)"],
    "evidence": [{"path": "out/billing.export/export-refused.txt", "exists": true, "non_empty": true}]
  }
}
JSON
printf '%s\n' 'refused: cli/shop export --env staging needs a write grant for staging' >"$out/export-refused.txt"
