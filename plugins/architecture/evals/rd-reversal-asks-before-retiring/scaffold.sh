#!/usr/bin/env bash
# A service with two numbered decision records; 0002 chose GraphQL for the public API.
set -euo pipefail

git init -q -b main
git config user.name eval
git config user.email eval@example.invalid
mkdir -p docs/adr src/api

cat >docs/adr/0001-store-orders-in-postgresql.md <<'MD'
# 1. Store orders in PostgreSQL

Status: accepted

Orders need multi-row transactions, so we store them in PostgreSQL.

## Considered options

- MongoDB: cross-document transactions added latency.
MD

cat >docs/adr/0002-serve-the-public-api-over-graphql.md <<'MD'
# 2. Serve the public API over GraphQL

Status: accepted

Partners asked for flexible queries, so the public API is a GraphQL endpoint.

## Considered options

- REST: each partner view needed its own endpoint.
MD

cat >src/api/schema.graphql <<'GQL'
type Query {
  order(id: ID!): Order
}
GQL

git add -A
git commit -q -m "Orders service with two decision records"
