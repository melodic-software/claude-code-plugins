---
description: "Launch, ready-check, capture and clean up the identity server."
---

App: identity, built from `serve.py`. Driving tool: playwright-cli.

Integrated apps: none

## Launch

`python3 serve.py idp --port 9100`

## Ready

`curl -fsS http://127.0.0.1:9100/health`

## Capture

none

## Cleanup

Stop the pid recorded at launch.

## Features

- Sign in | features/sign-in/README.md | entry points: 1 | sources: serve.py
