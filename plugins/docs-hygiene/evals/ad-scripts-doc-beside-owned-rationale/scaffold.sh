#!/usr/bin/env bash
# Seed a docs page that restates package.json scripts beside one that restates config but owns a buried rate-limit rationale.
set -euo pipefail

mkdir -p docs config src
cat >package.json <<'JSON'
{
  "name": "tollgate",
  "version": "1.4.0",
  "private": true,
  "scripts": {
    "build": "tsc -p tsconfig.json",
    "test": "vitest run",
    "lint": "eslint .",
    "start": "node dist/server.js",
    "db:migrate": "node dist/migrate.js"
  }
}
JSON
cat >config/payments.json <<'JSON'
{
  "provider": "acme-pay",
  "maxRetries": 3,
  "backoffMs": 400,
  "requestTimeoutMs": 2500
}
JSON
cat >src/payments.ts <<'TS'
import settings from "../config/payments.json";

export async function charge(send: () => Promise<Response>): Promise<Response> {
  let last: Response | undefined;
  for (let attempt = 0; attempt <= settings.maxRetries; attempt++) {
    last = await send();
    if (last.status !== 429 && last.status < 500) return last;
    await new Promise((r) => setTimeout(r, settings.backoffMs * 2 ** attempt));
  }
  return last as Response;
}
TS
cat >docs/commands.md <<'MD'
# Commands

These are the commands you can run in this repository.

| Command | What it does |
|---|---|
| `npm run build` | Compiles TypeScript with `tsc -p tsconfig.json`. |
| `npm test` | Runs the tests with `vitest run`. |
| `npm run lint` | Lints with `eslint .`. |
| `npm start` | Starts the server from `dist/server.js`. |
| `npm run db:migrate` | Runs the database migrations from `dist/migrate.js`. |
MD
cat >docs/payments-retries.md <<'MD'
# Payment retries

Charges go to Acme Pay through `charge()` in `src/payments.ts`. Settings live in
`config/payments.json`.

| Setting | Value |
|---|---|
| `maxRetries` | 3 |
| `backoffMs` | 400, doubled on each attempt |
| `requestTimeoutMs` | 2500 |

A request is retried on HTTP 429 and on any 5xx. Other statuses return at once. The retry count
stays at 3, not 5: at 5, a retry storm in March pushed us past Acme Pay's limit of 10 requests per
second per merchant account, and Acme locked the account for an hour. Raise it only after Acme
raises that limit in writing.
MD
