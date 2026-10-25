---
description: "Launch, ready-check, capture and clean up the shop app."
---

## Launch

1. `python3 -m venv .venv`
2. `. .venv/bin/activate`
3. `pip install -r requirements.txt`
4. `SHOP_MAIL=off python3 shop/server.py --port 8080`

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
