---
description: "Launch, ready-check, capture and clean up the shop app."
---

## Launch

`python3 shop/server.py`

## Ready

`curl -fsS http://127.0.0.1:8080/health`

## Capture

| Kind | Tool |
|---|---|
| logs | `tail -n 200 shop/server.log` |

## Cleanup

Stop the pid recorded at launch.

## Features

- Export invoices | features/billing/export/README.md | entry points: 2 | sources: shop/billing/export/**
