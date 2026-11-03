#!/usr/bin/env bash
set -euo pipefail

git init -q -b main
git config user.name eval
git config user.email eval@example.invalid
mkdir -p src/payments src/subscriptions db/migrations deploy tests .work/review-target/design

cat >package.json <<'JSON'
{
  "name": "mealbox-api",
  "version": "2.4.1",
  "private": true,
  "type": "module",
  "scripts": {
    "start": "node dist/server.js",
    "build": "tsc",
    "test": "vitest run"
  },
  "dependencies": {
    "express": "^4.19.0",
    "pg": "^8.12.0"
  },
  "devDependencies": {
    "typescript": "^5.5.0",
    "vitest": "^2.0.0"
  }
}
JSON

cat >src/server.ts <<'TS'
import express from "express";
import pg from "pg";
import { SubscriptionRepo } from "./subscriptions/repo.js";
import { formatCents } from "./format.js";

const pool = new pg.Pool({ connectionString: process.env.DATABASE_URL });
const repo = new SubscriptionRepo(pool);
const app = express();

app.get("/healthz", (_req, res) => res.send("ok"));

app.get("/subscriptions/:id", async (req, res) => {
  const sub = await repo.get(req.params.id);
  if (!sub) return res.sendStatus(404);
  res.json({ ...sub, price: formatCents(sub.priceCents) });
});

app.listen(Number(process.env.PORT ?? 8080));
TS

cat >src/format.ts <<'TS'
export function formatCents(cents: number): string {
  return `$${(cents / 100).toFixed(2)}`;
}

export function parsePrice(text: string): number {
  return Math.round(Number(text.replace(/[$,]/g, "")) * 100);
}
TS

cat >src/payments/client.ts <<'TS'
export type ChargeResult =
  | { status: "paid"; chargeId: string }
  | { status: "declined"; code: string };

export class GatewayUnavailable extends Error {}

export class PaymentClient {
  constructor(
    private readonly baseUrl: string,
    private readonly apiKey: string,
  ) {}

  async charge(customerId: string, amountCents: number): Promise<ChargeResult> {
    const response = await fetch(`${this.baseUrl}/charges`, {
      method: "POST",
      headers: { authorization: `Bearer ${this.apiKey}`, "content-type": "application/json" },
      body: JSON.stringify({ customerId, amountCents }),
    });
    if (response.status === 402) {
      const body = (await response.json()) as { code: string };
      return { status: "declined", code: body.code };
    }
    if (!response.ok) {
      throw new GatewayUnavailable(`gateway answered ${response.status}`);
    }
    const body = (await response.json()) as { id: string };
    return { status: "paid", chargeId: body.id };
  }
}
TS

cat >src/subscriptions/repo.ts <<'TS'
import type pg from "pg";

export interface Subscription {
  id: string;
  customerId: string;
  priceCents: number;
  status: "active" | "past_due" | "cancelled";
  nextRenewalAt: Date;
}

const COLUMNS = `id, customer_id AS "customerId", price_cents AS "priceCents", status,
  next_renewal_at AS "nextRenewalAt"`;

export class SubscriptionRepo {
  constructor(private readonly pool: pg.Pool) {}

  async get(id: string): Promise<Subscription | undefined> {
    const result = await this.pool.query(`SELECT ${COLUMNS} FROM subscriptions WHERE id = $1`, [id]);
    return result.rows[0];
  }

  async findDue(now: Date, limit = 200): Promise<Subscription[]> {
    const result = await this.pool.query(
      `SELECT ${COLUMNS} FROM subscriptions
       WHERE status = 'active' AND next_renewal_at <= $1
       ORDER BY next_renewal_at LIMIT $2`,
      [now, limit],
    );
    return result.rows;
  }

  async setRenewal(id: string, status: Subscription["status"], next: Date): Promise<void> {
    await this.pool.query(
      "UPDATE subscriptions SET status = $2, next_renewal_at = $3 WHERE id = $1",
      [id, status, next],
    );
  }
}
TS

cat >db/migrations/003_next_renewal.sql <<'SQL'
ALTER TABLE subscriptions ADD COLUMN next_renewal_at timestamptz NOT NULL DEFAULT now();
CREATE INDEX subscriptions_active_next_renewal_idx
  ON subscriptions (next_renewal_at)
  WHERE status = 'active';
SQL

cat >deploy/compose.yaml <<'YAML'
services:
  api:
    image: registry.example.invalid/mealbox-api:2.4.1
    env_file: api.env
    deploy:
      replicas: 3
    ports:
      - "8080"
    healthcheck:
      test: ["CMD", "wget", "-qO-", "http://localhost:8080/healthz"]
  db:
    image: postgres:16
    volumes:
      - dbdata:/var/lib/postgresql/data
volumes:
  dbdata: {}
YAML

cat >tests/format.test.ts <<'TS'
import { describe, expect, it } from "vitest";
import { formatCents, parsePrice } from "../src/format.js";

describe("format", () => {
  it("round-trips a price", () => {
    expect(parsePrice(formatCents(1999))).toBe(1999);
  });
});
TS

cat >.work/review-target/PLAN.md <<'MD'
# Automatic subscription renewals

## Brief

### Problem
Weekly meal-box subscriptions renew through a spreadsheet an operator exports and uploads to the
payment portal each Monday. Renewals run late, and declines are found days afterwards.

### Goal
The API charges each subscription when it falls due and keeps its status accurate.

### Acceptance criteria
- AC1: Within ten minutes of `next_renewal_at`, an active subscription is charged its `priceCents`
  once, and on a paid result `next_renewal_at` moves forward seven days.
- AC2: On a declined result the subscription moves to `past_due`, keeps its `next_renewal_at`, and
  is not charged again until support reactivates it.
- AC3: Support can list the last 50 renewal attempts for a subscription through
  `GET /subscriptions/:id/renewals`.

### Out-of-scope
- Retrying a declined card automatically.
- Customer-facing receipts and decline emails.

### Captured assumptions
- Quality bar: production
- All plans bill weekly.

## Plan

### Phase 1: Renewal of one subscription [TODO]
**Satisfies:** AC1, AC2

- Add `src/subscriptions/renewal.ts` with `renewOne(sub, deps)`.
- Inside a `try`, call `PaymentClient.charge`, then `repo.setRenewal(id, "active", next)` with `next`
  seven days after the current `nextRenewalAt`.
- `catch (err)`: when `err` is `PaymentDeclined`, call `repo.setRenewal(id, "past_due", current)`.
  Any other error is logged, and the subscription stays due for the next sweep.

**Sanity Check:** in a unit test with a stubbed client, a paid charge leaves `active` and a date seven
days later; a stub that throws `PaymentDeclined` leaves `past_due` and the same date.

### Phase 2: Scheduled sweep [TODO]
**Satisfies:** AC1

- Add `runRenewalSweep(deps)` to `renewal.ts`: `repo.findDue(new Date())`, then `renewOne` for each
  row in order.
- In `src/server.ts`, after `app.listen`, start `setInterval(() => runRenewalSweep(deps), 5 * 60_000)`
  so the sweep ships with the API and needs no new service to deploy.
- `findDue` and `subscriptions_active_next_renewal_idx` from `db/migrations/003_next_renewal.sql`
  serve the sweep as they stand, so this phase has no schema change.

**Sanity Check:** start the API locally with one due row in the database. Within five minutes the row
has a `next_renewal_at` seven days later and the stub gateway has one request.

### Phase 3: Renewal attempts [TODO]
**Satisfies:** AC3

- Add `db/migrations/004_renewal_attempts.sql` with `subscription_id`, `attempted_at`, `outcome` and
  `detail`, and an index on `(subscription_id, attempted_at DESC)`.
- `renewOne` writes one row per attempt.
- Add `GET /subscriptions/:id/renewals`, newest first, limit 50.

**Sanity Check:** after one paid and one declined attempt in a test database, the endpoint lists two
rows, newest first.

### Phase 4: Money module [TODO]
**Satisfies:** Maintainability

- Move `formatCents` and `parsePrice` from `src/format.ts` into a new `src/money.ts` with a branded
  `Cents` type.
- Update the imports in `src/server.ts` and `tests/format.test.ts`, and delete `src/format.ts`.

**Sanity Check:** `npm run build` and `npm test` both pass.

### Load-bearing assumptions
- `PaymentClient.charge` in `src/payments/client.ts` throws `PaymentDeclined` on a card decline, so
  the `catch` in Phase 1 is the whole decline path.
- A sweep finishes well inside five minutes: `findDue` caps at 200 rows.
- The gateway answers within a few seconds.

### Test strategy
Vitest unit tests cover `renewOne` with a stubbed client and repository. One integration test runs
`runRenewalSweep` against a Postgres test database and a stub gateway.

### Files affected
| File | Action |
|---|---|
| `src/subscriptions/renewal.ts` | create |
| `src/server.ts` | modify: interval, attempts endpoint, money import |
| `db/migrations/004_renewal_attempts.sql` | create |
| `src/money.ts` | create |
| `src/format.ts` | delete |
| `tests/renewal.test.ts` | create |
| `tests/format.test.ts` | modify: money import |
MD

cat >.work/review-target/design/design-resolution.md <<'MD'
outcome: early-exit
tier: C
reason: The change adds one worker module to the API and uses the existing repository and payment client.
MD
