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

`cli/shop ready <run dir>`

It exits non-zero when nothing answers on 127.0.0.1:18080, when the pid listening there is not the
one in the run's launch record, or when the API rejects the buyer credential.

build: not exposed

Telemetry: none

## Capture

none

## Cleanup

Stop the pid recorded at launch.
