---
description: "Launch, ready-check, capture and clean up the identity server."
---

App: identity, built from `serve.py`. Driving tool: playwright-cli.

Integrated apps: none

## Launch

`python3 serve.py idp --url <environment url>`

## Ready

`python3 serve.py health <environment url>`

## Capture

none

## Cleanup

Stop the pid recorded at launch.

## Features

- Sign in | features/sign-in/README.md | entry points: 1 | sources: serve.py
