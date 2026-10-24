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
| threads | `py-spy dump --pid <pid>` |

## Cleanup

Stop the pid recorded at launch.
