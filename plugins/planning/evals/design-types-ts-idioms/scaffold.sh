#!/usr/bin/env bash
# A TypeScript shipment poller with a retry policy literal. The graded outcome is the idiom the
# skill's TypeScript file names for a literal: satisfies.
set -euo pipefail

git init -q -b main
git config user.name eval
git config user.email eval@example.invalid
mkdir -p src .work/shipment-poller/design

printf '.work/\nnode_modules/\n' >.gitignore

cat >package.json <<'JSON'
{
  "name": "shipment-poller",
  "type": "module",
  "devDependencies": { "typescript": "^5.6.0" }
}
JSON

cat >tsconfig.json <<'JSON'
{ "compilerOptions": { "strict": true, "target": "es2022", "module": "nodenext" }, "include": ["src"] }
JSON

cat >src/config.ts <<'TS'
export function loadPollerConfig() {
  return {
    endpoint: process.env.CARRIER_URL ?? "https://carrier.example.invalid",
    intervalMs: 5000,
    batchSize: 20,
  };
}
TS

cat >src/labels.ts <<'TS'
export function recordLabel(shipmentId: string, carrierId: string, label: string): void {
  console.log(shipmentId, carrierId, label);
}
TS

cat >.work/shipment-poller/PLAN.md <<'MD'
# Shipment poller

## Brief

### Goal
A poller reads shipments from the carrier on a timer and records a label for each. It is started
with the values loadPollerConfig (src/config.ts) returns. It retries a failed read with a policy set once in code:
3 attempts, exponential backoff. A shipment has an id, a carrier id and its parcels. The carrier
sends no shipment without a parcel, and printing a shipment prints its first parcel's label.

### Acceptance criteria
- Each polled shipment reaches recordLabel (src/labels.ts).

### Captured assumptions
- Quality bar: production
MD

cat >.work/shipment-poller/design/design-threads.md <<'MD'
# Design threads

## Placement: resolved
The poller lives in src/poller.ts and the shipment types in src/shipment.ts.
MD

git add .
git commit -q -m "feat: poller config and labels"
