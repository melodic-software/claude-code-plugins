#!/usr/bin/env bash
# Seed an agent-facing module map that restates the import graph of six modules with no way to regenerate or recheck it.
set -euo pipefail

mkdir -p docs/agents src/billing src/catalog src/orders src/shipping src/notify src/shared
cat >src/shared/db.ts <<'TS'
export const db = { query: async (sql: string) => [] as unknown[] };
TS
cat >src/catalog/index.ts <<'TS'
import { db } from "../shared/db";
export const findSku = (sku: string) => db.query(`select * from sku where id = '${sku}'`);
TS
cat >src/billing/index.ts <<'TS'
import { db } from "../shared/db";
export const invoice = (orderId: string) => db.query(`insert into invoice values ('${orderId}')`);
TS
cat >src/notify/index.ts <<'TS'
export const email = async (to: string, body: string) => ({ to, body });
TS
cat >src/shipping/index.ts <<'TS'
import { db } from "../shared/db";
import { email } from "../notify";
export const ship = async (orderId: string) => {
  await db.query(`update orders set shipped = true where id = '${orderId}'`);
  return email("ops@example.com", `shipped ${orderId}`);
};
TS
cat >src/orders/index.ts <<'TS'
import { findSku } from "../catalog";
import { invoice } from "../billing";
import { ship } from "../shipping";
import { email } from "../notify";
export const placeOrder = async (orderId: string, sku: string) => {
  await findSku(sku);
  await invoice(orderId);
  await ship(orderId);
  return email("customer@example.com", `order ${orderId} placed`);
};
TS
cat >AGENTS.md <<'MD'
# AGENTS.md

TypeScript service. Before changing imports between modules under `src/`, read
`docs/agents/module-map.md`.
MD
cat >docs/agents/module-map.md <<'MD'
# Module map

Which module under `src/` imports which. Read this before adding an import between modules.

| Module | Imports from |
|---|---|
| `src/orders` | `src/catalog`, `src/billing`, `src/shipping`, `src/notify` |
| `src/shipping` | `src/shared`, `src/notify` |
| `src/billing` | `src/shared` |
| `src/catalog` | `src/shared` |
| `src/notify` | nothing |
| `src/shared` | nothing |

`src/orders` is the only module that imports `src/billing`. `src/notify` and `src/shared` import
no other module.
MD
