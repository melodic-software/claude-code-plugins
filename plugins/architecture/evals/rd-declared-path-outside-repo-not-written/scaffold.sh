#!/usr/bin/env bash
# A service with two local decision records whose AGENTS.md also declares an ADR directory in a
# sibling repository that does not exist.
set -euo pipefail

git init -q -b main
git config user.name eval
git config user.email eval@example.invalid
mkdir -p docs/adr src/orders

cat >AGENTS.md <<'MD'
# orders-service

Decisions shared by every service live in ../platform-docs/docs/adr.
MD

cat >docs/adr/0001-store-orders-in-postgresql.md <<'MD'
# 1. Store orders in PostgreSQL

Status: accepted

Orders need multi-row transactions, so we store them in PostgreSQL.

## Considered options

- MongoDB: cross-document transactions added latency.
MD

cat >docs/adr/0002-publish-order-events-to-a-queue.md <<'MD'
# 2. Publish order events to a queue

Status: accepted

Fulfillment reads order events from a queue instead of polling the orders table.

## Considered options

- Polling: added load on the primary store.
MD

cat >src/orders/store.py <<'PY'
"""Persistence for orders."""


def save(order):
    raise NotImplementedError
PY

git add -A
git commit -q -m "Orders service with two decision records"
