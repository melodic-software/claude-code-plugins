#!/usr/bin/env bash
set -euo pipefail

git init -q -b main
git config user.name eval
git config user.email eval@example.invalid

mkdir -p src migrations deploy .work/review-target/design

cat > package.json <<'EOF'
{
  "name": "billing-runner",
  "version": "2.7.0",
  "private": true,
  "type": "module",
  "scripts": {
    "build": "tsc -p .",
    "start:web": "node dist/web.js",
    "test": "node --test dist/test"
  },
  "dependencies": {
    "express": "^4.19.2",
    "pdf-lib": "^1.17.1",
    "pg": "^8.12.0"
  },
  "devDependencies": {
    "@types/express": "^4.17.21",
    "@types/pg": "^8.11.6",
    "typescript": "^5.5.4"
  }
}
EOF

cat > src/db.ts <<'EOF'
import pg from "pg";

export const pool = new pg.Pool({
  connectionString: process.env.DATABASE_URL,
  max: 10,
});
EOF

cat > src/delivery.ts <<'EOF'
import { mkdir, writeFile } from "node:fs/promises";
import { join } from "node:path";

const root = process.env.PDF_ROOT ?? "/var/lib/billing/pdfs";
const mailUrl = process.env.MAIL_API_URL ?? "http://mail.internal/send";

export async function storePdf(tenantId: string, period: string, pdf: Uint8Array): Promise<string> {
  const dir = join(root, tenantId);
  await mkdir(dir, { recursive: true });
  const key = join(tenantId, `${period}-${Date.now()}.pdf`);
  await writeFile(join(root, key), pdf);
  return key;
}

export async function emailInvoice(tenantId: string, invoiceId: number, pdfKey: string): Promise<void> {
  const response = await fetch(mailUrl, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ template: "invoice", tenantId, invoiceId, pdfKey }),
  });
  if (!response.ok) {
    throw new Error(`mail service returned ${response.status}`);
  }
}
EOF

cat > src/invoice.ts <<'EOF'
import { PDFDocument } from "pdf-lib";
import { pool } from "./db.js";
import { emailInvoice, storePdf } from "./delivery.js";

interface UsageLine {
  description: string;
  cents: number;
}

async function renderPdf(tenantId: string, period: string, lines: UsageLine[]): Promise<Uint8Array> {
  const doc = await PDFDocument.create();
  const page = doc.addPage();
  page.drawText(`Invoice for ${tenantId}, ${period}`, { x: 50, y: 780, size: 14 });
  lines.forEach((line, index) => {
    const dollars = (line.cents / 100).toFixed(2);
    page.drawText(`${line.description}: ${dollars}`, { x: 50, y: 750 - index * 16, size: 10 });
  });
  return doc.save();
}

export async function createInvoice(tenantId: string, period: string): Promise<number> {
  const usage = await pool.query<UsageLine>(
    "SELECT description, cents FROM usage_lines WHERE tenant_id = $1 AND period = $2",
    [tenantId, period],
  );
  const total = usage.rows.reduce((sum, line) => sum + line.cents, 0);
  const pdfKey = await storePdf(tenantId, period, await renderPdf(tenantId, period, usage.rows));
  const inserted = await pool.query<{ id: number }>(
    "INSERT INTO invoices (tenant_id, period, total_cents, pdf_key) VALUES ($1, $2, $3, $4) RETURNING id",
    [tenantId, period, total, pdfKey],
  );
  await emailInvoice(tenantId, inserted.rows[0].id, pdfKey);
  return inserted.rows[0].id;
}
EOF

cat > src/web.ts <<'EOF'
import express from "express";
import { pool } from "./db.js";
import { createInvoice } from "./invoice.js";

const app = express();

function previousPeriod(now: Date): string {
  const first = new Date(Date.UTC(now.getUTCFullYear(), now.getUTCMonth() - 1, 1));
  return first.toISOString().slice(0, 7);
}

async function monthlyRun(): Promise<void> {
  const period = previousPeriod(new Date());
  const tenants = await pool.query<{ id: string }>("SELECT id FROM tenants WHERE active");
  for (const tenant of tenants.rows) {
    await createInvoice(tenant.id, period);
  }
}

setInterval(() => {
  const now = new Date();
  if (now.getUTCDate() === 1 && now.getUTCHours() === 2 && now.getUTCMinutes() === 0) {
    void monthlyRun();
  }
}, 60_000);

app.get("/health", (_req, res) => {
  res.send("ok");
});

app.listen(8080);
EOF

cat > migrations/001_init.sql <<'EOF'
CREATE TABLE tenants (
  id     text PRIMARY KEY,
  name   text NOT NULL,
  active boolean NOT NULL DEFAULT true
);

CREATE TABLE usage_lines (
  id          bigserial PRIMARY KEY,
  tenant_id   text NOT NULL REFERENCES tenants (id),
  period      text NOT NULL,
  description text NOT NULL,
  cents       integer NOT NULL
);

CREATE TABLE invoices (
  id          bigserial PRIMARY KEY,
  tenant_id   text NOT NULL REFERENCES tenants (id),
  period      text NOT NULL,
  total_cents integer NOT NULL,
  pdf_key     text NOT NULL,
  created_at  timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX invoices_tenant_period ON invoices (tenant_id, period);
EOF

cat > deploy/compose.yml <<'EOF'
services:
  web:
    image: registry.example.invalid/billing-runner:2.7.0
    command: node dist/web.js
    environment:
      DATABASE_URL: postgres://billing@pgbouncer:6432/billing
    deploy:
      replicas: 2
    stop_grace_period: 5s
  pgbouncer:
    image: registry.example.invalid/pgbouncer:1.22
    volumes:
      - ./pgbouncer.ini:/etc/pgbouncer/pgbouncer.ini:ro
  postgres:
    image: registry.example.invalid/postgres:16
    volumes:
      - pgdata:/var/lib/postgresql/data
volumes:
  pgdata: {}
EOF

cat > deploy/pgbouncer.ini <<'EOF'
[databases]
billing = host=postgres port=5432 dbname=billing

[pgbouncer]
listen_addr = 0.0.0.0
listen_port = 6432
auth_type = scram-sha-256
auth_file = /etc/pgbouncer/userlist.txt
pool_mode = transaction
default_pool_size = 20
max_client_conn = 200
EOF

cat > .work/review-target/PLAN.md <<'EOF'
# Plan: a durable invoice job queue

## Brief

### Problem

`src/web.ts` runs the monthly invoice run from a `setInterval` inside the web process. On the first
of the month both web replicas fire it, and any deploy during the run ends it halfway, so an
engineer spends the morning working out which of about 1,400 tenants still need an invoice. PDF
rendering on the event loop also pushes API latency up for the length of the run.

### Goal

Invoice generation runs as durable background work, apart from the API, and survives normal
operations without an engineer watching it.

### Acceptance criteria

- AC1: Each active tenant gets exactly one invoice per period, including across worker restarts and
  deploys during the run.
- AC2: Invoice work no longer runs in the web process.
- AC3: A job that fails with an error is tried again, up to three times, and is then visible as
  failed to whoever is on call.
- AC4: One tenant with a very large usage history cannot hold up the other tenants' invoices.

### Out-of-scope

- Changing the invoice layout or the email templates.
- Invoices for periods shorter than a month.
- Moving away from the current Postgres instance.

### Captured assumptions

- Quality bar: production
- The team of three runs the service with `deploy/compose.yml` and has no dedicated operations role.

## Proposal

### Recommendation

Add an `invoice_jobs` table to the existing database and a new `worker` service that drains it.

```sql
CREATE TABLE invoice_jobs (
  id         bigserial PRIMARY KEY,
  tenant_id  text NOT NULL REFERENCES tenants (id),
  period     text NOT NULL,
  status     text NOT NULL DEFAULT 'queued',
  attempts   integer NOT NULL DEFAULT 0,
  last_error text,
  UNIQUE (tenant_id, period)
);
```

A small scheduler in the worker inserts one row per active tenant on the first of the month with
`ON CONFLICT DO NOTHING`, so both replicas can run it. Each worker loop then claims one job in its
own short transaction:

```sql
UPDATE invoice_jobs SET status = 'running', attempts = attempts + 1
WHERE id = (SELECT id FROM invoice_jobs WHERE status = 'queued'
            ORDER BY id LIMIT 1 FOR UPDATE SKIP LOCKED)
RETURNING *;
```

The worker commits the claim, calls `createInvoice`, then sets `done`. On a thrown error it sets the
row back to `queued`, or to `failed` once `attempts` reaches three. An empty queue means the worker
sleeps five seconds and polls again.

Per-tenant counters limit how many PDF pages one tenant may render per minute. A tenant over its
limit goes back to `queued` until the next minute, which meets AC4.

### Why this approach

The queue lives in the database the invoices already live in, so there is no new client library,
and a job row is inspectable with plain SQL by anyone on the team. The claim transaction is short
and carries no PDF work, which is what lets it pass through the connection pooler.

A five-second poll costs one indexed query per worker per five seconds. `deploy/pgbouncer.ini` runs
`pool_mode = transaction`, where a session-level listener has no connection to stay on, so
LISTEN/NOTIFY through the pooler is not available to us. A month's run is about 1,400 jobs in one
night and has no latency requirement beyond finishing by morning.

### Alternatives considered

- **BullMQ.** A mature queue with retries and rate limiting built in. It needs Redis, a new stateful
  service that a team of three with no operations role would have to back up and watch.
- **A dedicated direct Postgres connection for LISTEN/NOTIFY.** It saves a few seconds of latency
  that nobody needs, for a second connection path past the pooler.
- **A cron container that runs the existing loop.** It moves the work out of the web process but
  still ends halfway on a deploy, and has no per-tenant isolation.

### Load-bearing assumptions

- `createInvoice` is idempotent: it upserts on `(tenant_id, period)` and sends the email only for a
  new invoice, so the worker can call it again for any tenant after a failed attempt.
- The largest tenant's PDF takes under a minute to render.
- About 1,400 active tenants, growing by about ten a month.

### Rollout

1. Add the `invoice_jobs` migration and the `worker` service, with the scheduler disabled.
2. Add a small Redis container to `deploy/compose.yml` to hold the per-tenant render counters.
3. Run one period by hand in staging and compare the invoices with last month's.
4. Enable the scheduler and delete `monthlyRun` and the `setInterval` from `src/web.ts`.
EOF

cat > .work/review-target/design/design-resolution.md <<'EOF'
outcome: early-exit
tier: C
reason: One table and one worker service behind the existing invoice function.
EOF
