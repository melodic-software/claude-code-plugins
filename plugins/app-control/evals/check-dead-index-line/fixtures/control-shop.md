---
description: "Launch, ready-check, capture and clean up the shop app."
---

## Launch

Run the `run-shop` skill (`.claude/skills/run-shop/SKILL.md`).

## Ready

`curl -fsS http://127.0.0.1:8080/healthz`

## Capture

| Kind | Tool |
|---|---|
| logs | `tail -n 200 shop/server.log` |

## Cleanup

Stop the pid recorded at launch.

## Features

- Cart | features/cart/README.md | entry points: 1 | sources: shop/cart.py
- Export invoices | features/billing/export/README.md | entry points: 2 | sources: shop/billing/export.py
- Refunds | features/refunds/README.md | entry points: 1 | sources: shop/cart.py
