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
| screenshot | `node tools/anim-capture.mjs --still --out <dir>` |
| animation | `node tools/anim-capture.mjs --frames --out <dir>` |

## Cleanup

Stop the pid recorded at launch.
