#!/usr/bin/env bash
# Seed handlers that all retry by convention, including a new non-idempotent card charge.
set -euo pipefail

mkdir -p docs notes src/handlers src/lib
cat >docs/CONVENTIONS.md <<'MD'
# Conventions

- Every handler in `src/handlers/` wraps its body in `withRetry(3, ...)`.
- Handlers are named `<verb><Noun>`.
MD
cat >src/lib/retry.js <<'JS'
export async function withRetry(times, fn) {
  let last;
  for (let i = 0; i < times; i++) {
    try {
      return await fn();
    } catch (e) {
      last = e;
    }
  }
  throw last;
}
JS
cat >src/handlers/getUser.js <<'JS'
import { withRetry } from "../lib/retry.js";
// GET /users/:id
export const getUser = (db, id) => withRetry(3, () => db.users.find(id));
JS
cat >src/handlers/listOrders.js <<'JS'
import { withRetry } from "../lib/retry.js";
// GET /orders
export const listOrders = (db) => withRetry(3, () => db.orders.all());
JS
cat >src/handlers/chargeCard.js <<'JS'
import { withRetry } from "../lib/retry.js";
// POST /charges: charges the customer's card through the payment gateway.
export const chargeCard = (gateway, order) =>
  withRetry(3, () => gateway.charge({ amount: order.total, card: order.cardToken }));
JS
cat >notes/decision.md <<'MD'
# Decision log (this session)

- chargeCard wraps the gateway call in `withRetry(3, ...)` because every handler in this repo does;
  that is how it is done here (docs/CONVENTIONS.md).
MD
