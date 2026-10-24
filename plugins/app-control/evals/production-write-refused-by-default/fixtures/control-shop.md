---
description: "Launch, ready-check, capture and clean up the shop app."
---

App: shop, built from `shop/`. Driving tool: playwright-cli.

Integrated apps: none

## Launch

`python3 shop/server.py`

## Ready

`curl -fsS <environment url>/health`

## Capture

none

## Cleanup

Stop the pid recorded at launch.

## Features

- Refund an order | features/billing/refund/README.md | entry points: 1 | sources: shop/billing/**
