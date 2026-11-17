#!/usr/bin/env bash
set -euo pipefail

skill=.claude/skills/control-shop
mkdir -p "$skill/features/cart" "$skill/config" src
cat >"$skill/SKILL.md" <<'MD'
---
description: "Launch, ready-check, capture and clean up the shop app."
---

- App: shop, built from `src/`
- Driving tool: playwright

## Launch

Run `npm start` from the repository root and record the pid it prints.

Data: a new directory per run under the system temp folder, migrated and seeded at launch
Side by side: yes, a port per run

## Ready

`curl -fsS <environment url>/healthz`

## Capture

none

## Cleanup

Stop the pid recorded at launch.

## Features

- Cart | features/cart/README.md | entry points: 1 | sources: src/cart.ts
MD
cat >"$skill/features/cart/README.md" <<'MD'
# cart

## Parts

- cart

## Sub-features

none

## Entry points

- the `cart` page: driven

## Reset

none

## Drive

- Open `/cart`. Result: the cart page shows.
- **Proof.** Result: the cart page lists its rows. Captures: screenshot

## Gotchas

none
MD
cat >"$skill/config/defaults.json" <<'JSON'
{
  "environment": "local",
  "environments": {
    "local": {
      "url": "http://127.0.0.1:4100",
      "sources": {
        "server-log": {"kind": "logs", "where": "<run data dir>/logs/server.log", "read": "unattended"},
        "shop-db": {"kind": "database", "where": "`cli/shop db query --read-only`", "read": "unattended"},
        "otel": {"kind": "telemetry", "where": "http://127.0.0.1:4318", "read": "unattended"}
      }
    },
    "staging": {
      "url": "https://staging.shop.example",
      "sources": {
        "staging-log": {"kind": "logs", "where": "`cli/shop logs --env staging`", "read": "attended"},
        "issues": {"kind": "tracker", "where": "https://tracker.example/shop", "read": "unattended"}
      }
    },
    "preview": {
      "extends": "local",
      "url": "http://127.0.0.1:4200",
      "sources": {
        "preview-issues": {"kind": "tracker", "where": "https://tracker.example/shop-preview", "read": "unattended"}
      }
    }
  },
  "safety": {}
}
JSON
printf 'local.json\n' >"$skill/config/.gitignore"
: >src/cart.ts
