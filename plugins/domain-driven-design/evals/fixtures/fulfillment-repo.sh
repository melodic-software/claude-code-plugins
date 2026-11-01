#!/usr/bin/env bash
# Writes a Northwind fulfillment repository with one bounded context under src/fulfillment and no
# glossary, context map, settings file or vocabulary convention anywhere.
set -euo pipefail
mkdir -p src/fulfillment
cat >README.md <<'MD'
# Northwind fulfillment

Packs orders and hands them to carriers.
MD
cat >src/fulfillment/shipment.ts <<'TS'
export interface Shipment {
  id: string;
  carrier: string;
  orderIds: string[];
}
TS
