---
description: "Launch, ready-check, capture and clean up the shop app."
---

App: shop, built from `shop/`. Driving tool: playwright-cli.

Integrated apps:

- identity | control-identity | repository: acme/identity

## Launch

`python3 shop/serve.py app --url <environment url> --identity <identity service url>`

## Ready

`python3 shop/serve.py health <environment url>`

## Capture

| Kind | Tier | Tool |
|---|---|---|
| logs | server | `tail -n 200 shop/server.log` |

## Cleanup

Stop the pid recorded at launch.

## Features

- Order history | features/orders/history/README.md | entry points: 1 | sources: shop/**
