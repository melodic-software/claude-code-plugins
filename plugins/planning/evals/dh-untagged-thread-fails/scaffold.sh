#!/usr/bin/env bash
# Seeds a design-threads artifact with one untagged open thread and one decided thread with no rationale.
set -euo pipefail

slice=.work/webhook-retry/design
mkdir -p "$slice"
cat >"$slice/design-threads.md" <<'MD'
# Design threads: outbound webhook retries

## T1. Delivery queue

- Options: in-memory queue; Postgres outbox table; managed message broker
- Status: RESOLVED
- Decision: Postgres outbox table polled by the delivery worker.
- Rationale: deliveries must survive a worker restart, and the service already owns a Postgres
  database, so the outbox adds no new infrastructure and commits atomically with the event.

## T2. Retry backoff policy

- Options: fixed 60-second interval; exponential backoff with jitter; per-endpoint configurable schedule
- Status: open

## T3. Signature scheme

- Options: HMAC-SHA256 over the body; asymmetric Ed25519 signatures
- Status: RESOLVED
- Decision: HMAC-SHA256.

## T4. Dead-letter retention

- Options: 7 days; 30 days; 90 days
- Status: TAGGED-DEFERRED
- Research tag: confirm the legal retention rules for stored webhook payloads before choosing.

## T5. Endpoint ownership

- Options: platform team registers endpoints; each tenant registers its own
- Status: RESOLVED
- Decision: each tenant registers and rotates its own endpoints through the settings API.
- Rationale: tenants already self-serve API keys there, and a platform-run registry would put the
  platform team on the path of every tenant integration change.
MD
