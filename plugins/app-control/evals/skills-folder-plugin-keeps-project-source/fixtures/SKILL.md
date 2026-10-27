---
name: control-shop
description: "Launch, ready-check, drive, capture and clean up the shop app."
---

## Launch

`python3 shop/server.py`

## Ready

`curl -fsS http://127.0.0.1:8080/health`

## Capture

| Kind | Tool |
|---|---|
| logs | `shop/server.log` |

## Cleanup

Stop the pid recorded at launch.
