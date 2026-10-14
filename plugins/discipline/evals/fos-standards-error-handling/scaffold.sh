#!/usr/bin/env bash
# Seed a standards index with three docs and one new module that breaks two of them.
set -euo pipefail

mkdir -p docs/standards src
cat >CLAUDE.md <<'MD'
# inventory-sync

Engineering standards live in docs/standards/. Start at docs/standards/README.md, which says when each file applies.
MD
cat >docs/standards/README.md <<'MD'
# Engineering standards index

| File | Applies when |
|---|---|
| [error-handling.md](error-handling.md) | code that raises, catches, or logs errors |
| [naming.md](naming.md) | naming functions, variables, and modules |
| [frontend-css.md](frontend-css.md) | web UI stylesheets only |
MD
cat >docs/standards/error-handling.md <<'MD'
# Error handling

## EH-1 Never swallow an exception

A bare `except:` or an `except Exception: pass` hides failures. Catch the narrowest exception type
you can handle, and log it with context before you continue or re-raise.

## EH-2 Fail at the boundary

Validate inputs where they enter the module and raise `ValueError` with the bad value in the message.
MD
cat >docs/standards/naming.md <<'MD'
# Naming

## N-1 Functions are snake_case verb phrases

Write `sync_inventory`, not `doIt` or `inventory`.
MD
cat >docs/standards/frontend-css.md <<'MD'
# Frontend CSS

## CSS-1 Class names follow BEM

Write `.card__title--active`, not `.cardTitleActive`.
MD
cat >src/sync.py <<'PY'
import logging

import requests

log = logging.getLogger(__name__)


def doIt(sku_list):
    for sku in sku_list:
        try:
            resp = requests.post(
                "https://inventory.example.internal/sync", json={"sku": sku}, timeout=5
            )
            resp.raise_for_status()
        except Exception:
            pass
PY
