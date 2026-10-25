---
name: control-other
description: "Launch, ready-check, drive, capture and clean up the other app."
---

## Launch

`python3 other/server.py`

## Ready

`curl -fsS http://127.0.0.1:9090/health`

## Cleanup

Stop the pid recorded at launch.
