#!/usr/bin/env bash
set -euo pipefail

git init -q -b main
git config user.name eval
git config user.email eval@example.invalid
mkdir -p docs/adr

cat >docs/adr/0001-store-orders-in-postgresql.md <<'MD'
# 1. Store orders in PostgreSQL

Status: accepted

Orders need multi-row transactions, so we store them in PostgreSQL.

## Considered options

- MongoDB: cross-document transactions added latency.
MD

git add -A
git commit -q -m "Orders service with one decision record"
