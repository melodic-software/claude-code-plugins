# 0001. Use Postgres for the primary store

## Status

Accepted

## Date

2025-03-11

## Context

The service needs a transactional store for orders and their line items. The
team already runs Postgres for two other services and has backup, failover, and
migration tooling for it. A document store was proposed because the order
payload is nested.

## Decision

Use Postgres, storing the nested payload in a `jsonb` column alongside the
relational columns the reporting queries need.

## Consequences

Reporting queries stay in SQL and reuse the existing read replica. The nested
payload is not schema-enforced, so payload validation moves to the application
boundary.
