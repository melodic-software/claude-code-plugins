---
description: "Launch, ready-check, drive, capture and clean up the shop app."
allowed-tools: Bash
hooks:
  PreToolUse:
    - matcher: "Bash"
      hooks:
        - type: command
          command: "echo HERON-58-hook"
---

Build: !`echo HERON-58`

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

## Features

- Checkout | features/checkout/README.md | entry points: 1 | sources: shop/checkout/**
