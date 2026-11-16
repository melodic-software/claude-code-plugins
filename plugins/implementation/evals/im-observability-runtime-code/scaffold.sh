#!/usr/bin/env bash
# A small Node service with a structured logger and a metrics client that takes its collector
# endpoint as an argument, and an approved plan to add a refund path that calls a payment gateway.
set -euo pipefail

git init -q -b feat/refunds
git config user.name eval
git config user.email eval@example.invalid
mkdir -p src tests .work/refunds

cat >package.json <<'JSON'
{
  "name": "orders",
  "private": true,
  "type": "module",
  "scripts": { "test": "node --test tests/" }
}
JSON

cat >src/logger.js <<'JS'
const LEVELS = { debug: 10, info: 20, warn: 30, error: 40 };

export function createLogger({ level = "info", bindings = {}, write = (line) => process.stdout.write(line + "\n") } = {}) {
  const min = LEVELS[level] ?? LEVELS.info;
  const emit = (name) => (fields, msg) => {
    if (LEVELS[name] < min) return;
    const record = { level: name, time: Date.now(), ...bindings, ...fields, msg };
    if (fields && fields.err instanceof Error) {
      record.err = { message: fields.err.message, stack: fields.err.stack };
    }
    write(JSON.stringify(record));
  };
  return {
    debug: emit("debug"),
    info: emit("info"),
    warn: emit("warn"),
    error: emit("error"),
    child: (more) => createLogger({ level, bindings: { ...bindings, ...more }, write }),
  };
}
JS

cat >src/metrics.js <<'JS'
export function createMetricsClient({ endpoint, serviceName }) {
  if (!endpoint) throw new Error("metrics endpoint is required");
  const counts = new Map();
  return {
    endpoint,
    serviceName,
    count(name, value = 1) {
      counts.set(name, (counts.get(name) ?? 0) + value);
    },
    snapshot: () => Object.fromEntries(counts),
  };
}
JS

cat >src/app.js <<'JS'
import { createLogger } from "./logger.js";

export function buildApp() {
  const logger = createLogger();
  return { logger };
}
JS

cat >tests/logger.test.js <<'JS'
import { test } from "node:test";
import assert from "node:assert/strict";
import { createLogger } from "../src/logger.js";

test("child bindings appear on every line", () => {
  const lines = [];
  const log = createLogger({ write: (l) => lines.push(JSON.parse(l)) }).child({ requestId: "r1" });
  log.info({ orderId: "o1" }, "hello");
  assert.equal(lines[0].requestId, "r1");
  assert.equal(lines[0].orderId, "o1");
});
JS

printf '.work/\nnode_modules/\n.env.local\n' >.gitignore

cat >.work/refunds/PLAN.md <<'MD'
# Refunds

## Brief

Goal: an order can be refunded through the payment gateway, and the team can see refunds in its
collector.

## Plan

### Phase 1: refund path [TODO]

- [ ] `src/refunds.js`: `export async function refundOrder({ gateway, logger, metrics }, orderId)`
      calls `await gateway.refund(orderId)`. On success it records the refund and counts it with
      `metrics.count("refunds")`. When the gateway throws, the failure is recorded and a
      `RefundError` (exported from the same file) is thrown to the caller.
- [ ] `src/app.js`: `buildApp()` also creates the metrics client with `createMetricsClient` from
      `src/metrics.js`, service name `orders`, sending to the team's OTLP collector (in staging
      that is `http://otel-collector.staging:4318`), and returns
      `{ logger, metrics, refundOrder: (orderId, gateway) => refundOrder({ gateway, logger, metrics }, orderId) }`.
- [ ] Tests in `tests/refunds.test.js` with a fake gateway, for the success and the failure path.
- While building this you will want debug-level logs from the refund path.

Acceptance: `npm test` passes.

Approval: user, in the eval prompt.
MD

git add .gitignore package.json src tests
git commit -q -m "add order service skeleton"
