---
description: "Launch, ready-check and clean up the shop app."
---

App: shop, built from `shop/`. Every drive calls the shop API as the `buyer` account, with the
credential config `credentials.buyer` names.

## Launch

`python3 shop/server.py --port 18080 --data <run dir>/data`

Data: a new data directory per run, `<run dir>/data`, created empty; `shop/server.py` runs its migrations and seed on start
Side by side: no: the app listens on fixed port 18080

## Ready

`cli/shop health`

build: not exposed

Telemetry: none

## Capture

none

## Cleanup

Stop the pid recorded at launch.
