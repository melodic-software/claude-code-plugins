#!/usr/bin/env bash
set -euo pipefail

git init -q -b main
git config user.name eval
git config user.email eval@example.invalid

mkdir -p src/seats src/checkout src/db deploy docs/vendor .work/review-target/design

cat >package.json <<'JSON'
{
  "name": "boxoffice-api",
  "version": "4.3.0",
  "private": true,
  "type": "module",
  "engines": { "node": ">=22" },
  "scripts": {
    "build": "tsc -p .",
    "test": "vitest run"
  },
  "dependencies": {
    "fastify": "4.28.1",
    "holdfast": "2.9.4",
    "ioredis": "5.4.1"
  },
  "devDependencies": {
    "typescript": "5.5.4",
    "vitest": "2.0.5"
  }
}
JSON

cat >src/seats/holds.ts <<'TS'
import { acquire, release, type Lock } from "holdfast";
import { redis } from "../db/redis.js";

const HOLD_MS = 10 * 60 * 1000;
const open = new Map<string, Lock>();

export async function placeHold(seatId: string, buyerId: string): Promise<boolean> {
  const lock = await acquire(redis, `seat:${seatId}`, { ttlMs: HOLD_MS, owner: buyerId });
  if (lock === null) return false;
  open.set(seatId, lock);
  return true;
}

export async function dropHold(seatId: string): Promise<void> {
  const lock = open.get(seatId);
  if (lock === undefined) return;
  await release(redis, lock);
  open.delete(seatId);
}
TS

cat >src/checkout/complete.ts <<'TS'
import { extend as extendLock } from "holdfast";
import { redis } from "../db/redis.js";
import { chargeBuyer } from "./payments.js";
import { dropHold } from "../seats/holds.js";

const PAYMENT_WINDOW_MS = 5 * 60 * 1000;

export async function completeCheckout(seatId: string, buyerId: string, cardToken: string) {
  const extended = await extendLock(redis, `seat:${seatId}`, {
    ttlMs: PAYMENT_WINDOW_MS,
    owner: buyerId,
  });
  if (!extended) throw new Error("hold expired");
  const receipt = await chargeBuyer(buyerId, cardToken);
  await dropHold(seatId);
  return receipt;
}
TS

cat >src/db/schema.sql <<'SQL'
CREATE TABLE seats (
  seat_id    TEXT PRIMARY KEY,
  event_id   TEXT NOT NULL,
  section    TEXT NOT NULL,
  sold_to    TEXT
);

CREATE TABLE orders (
  order_id   TEXT PRIMARY KEY,
  seat_id    TEXT NOT NULL REFERENCES seats (seat_id),
  buyer_id   TEXT NOT NULL,
  paid_at    TIMESTAMP NOT NULL
);
SQL

cat >deploy/compose.yaml <<'YAML'
services:
  api:
    image: node:22-alpine
    command: node dist/server.js
    deploy:
      replicas: 4
      update_config:
        parallelism: 1
        delay: 60s
    environment:
      REDIS_URL: redis://holds-redis:6379
      EMBERSTORE_URL: emberstore://seats-db:7300/boxoffice
  holds-redis:
    image: redis:7
  seats-db:
    image: emberstore:6.2.0
    volumes:
      - seats:/var/lib/emberstore
volumes:
  seats:
YAML

cat >docs/vendor/holdfast-changelog.md <<'MD'
# Holdfast changelog

## 2.9.4

- Final 2.x release. The maintainers have ended support for Holdfast.

## 2.9.0

- `extend(client, name, { ttlMs, owner })` moves the expiry of a named lock for its owner.

## 2.0.0

- `acquire` stores a lock under the Redis key `hf:<name>`.
MD

cat >docs/vendor/leaseline-notes.md <<'MD'
# Leaseline notes

- Node 20 or later.
- `acquire(client, name, { ttlMs, holder })` returns a `Lease`, or `null` when `name` is taken.
- `lease.renew(ttlMs)` and `lease.release()` act on the `Lease` object.
- `renewByName(client, name, { ttlMs, holder })` is available from 1.4.
- Leases are stored under the Redis key `lease:<name>`, as a hash.
- Leaseline reads and writes keys with that prefix and no others.
- Current release: 1.6.2, actively maintained.
MD

cat >docs/vendor/emberstore-release-notes.md <<'MD'
# Emberstore release notes

## 6.2

- Faster secondary index builds.

## 6.1

- Row claims: `CLAIM <table> <key> FOR <owner> UNTIL <time>` sets a `HOLD_UNTIL` on a row.
- A row with an unexpired `HOLD_UNTIL` refuses a `CLAIM` from a different owner.
- A claim lapses at its time with no sweep job.
- The owner moves the time with `CLAIM ... UNTIL <later time>`.

## 6.0

- Serializable transactions by default.
MD

cat >.work/review-target/design/design-resolution.md <<'MD'
---
outcome: early-exit
tier: C
reason: the Brief names the seat-hold decision and its options; no type or module design is open
---
MD

cat >.work/review-target/PLAN.md <<'MD'
# Seat holds on a supported component

## Brief

### Problem

A buyer who picks a seat gets a ten-minute hold while they check out. Holds run on Holdfast, a
locking library over Redis. Its maintainers have ended support, and a security fix in its Redis
client code would now be ours to carry.

### Goal

Move seat holds off Holdfast with no change in what buyers see.

### Acceptance criteria

- AC1: A seat has at most one holder at any moment, including during a deploy.
- AC2: A hold lapses ten minutes after it is placed, unless checkout has moved its expiry.
- AC3: `package.json` no longer lists `holdfast`.

### Out-of-scope

- Seat maps and pricing.
- The payment provider.
- Changing the ten-minute hold length.

### Captured assumptions

- Quality bar: production
- The API stays on Node and TypeScript.
- Peak traffic stays near the last on-sale, about 300 holds per second.

## Plan

### Decision

Replace Holdfast with Leaseline, keeping Redis as the store for holds.

### Why

- Holdfast 2.9.4 is its final release, so staying leaves AC3 and the support problem open.
- Leaseline has the same acquire and release shape, is actively maintained, and works over the
  `ioredis` client we already pass around.
- Holdfast is called from one module, `src/seats/holds.ts`, so the code change is small and stays
  behind `placeHold` and `dropHold`.
- Leaseline needs Node 20 or later. `package.json` and the API image are on Node 22.

### Phase 1: Swap the library in the holds module [TODO]

**Satisfies:** AC1, AC2

Add `leaseline` to `package.json`. Rewrite `placeHold` and `dropHold` in `src/seats/holds.ts` on
Leaseline's `acquire` and `Lease.release`, keeping the signatures and `HOLD_MS`. Put the new path
behind a `HOLDS_BACKEND` setting that defaults to `holdfast`.

**Sanity Check:** unit tests for `placeHold` pass on both settings against a local Redis.

### Phase 2: Switch production to Leaseline [TODO]

**Satisfies:** AC1, AC2

Set `HOLDS_BACKEND=leaseline` in `deploy/compose.yaml` and roll it out through the normal update
order. Holds last ten minutes at most, so there is no data to migrate: anything Holdfast wrote is
gone from Redis within ten minutes of the rollout.

**Sanity Check:** after the rollout, `redis-cli --scan --pattern 'lease:*'` shows new holds and the
hold error rate is flat on the API dashboard.

### Phase 3: Remove Holdfast [TODO]

**Satisfies:** AC3

Delete the `holdfast` branch and the `HOLDS_BACKEND` setting from `src/seats/holds.ts`. Remove
`holdfast` from `package.json` and refresh the lockfile.

**Sanity Check:** `npm run build` and `npm test` pass with the dependency gone.

### Load-bearing assumptions

- Redis stays at its current size; a lease hash is about the same size as a Holdfast key.
- Ten minutes remains the longest a hold can live.

### Test strategy

- Unit: one holder per seat under concurrent `placeHold` calls; a hold lapses at `HOLD_MS`.
- Integration: a full checkout against a local Redis on the Leaseline path.
- Production check: the Phase 2 scan and dashboard reading.
MD
