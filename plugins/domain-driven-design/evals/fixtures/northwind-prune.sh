#!/usr/bin/env bash
# Writes a Northwind Trading repository whose glossary at docs/glossary.md holds an implementation
# entry (Orders table) and an unused term (Backorder). The rejected word "parcel" appears in exactly
# three code files, each only inside an identifier (PascalCase, camelCase, snake_case).
set -euo pipefail
mkdir -p docs src/orders src/fulfillment
cat >README.md <<'MD'
# Northwind Trading

Order taking and fulfillment for the Northwind catalog.
MD
cat >docs/glossary.md <<'MD'
# Northwind Trading glossary

Language of the order-fulfillment domain.

**Order**

A buyer's confirmed request to purchase one or more catalog items.

Avoid: basket, cart

**Shipment**

One physical consignment handed to a carrier.

Avoid: parcel

**Backorder**

An order line waiting for stock that has not arrived.

**Orders table**

The `orders` table in Postgres, with columns `id`, `buyer_id` and `created_at`.
MD
cat >src/orders/order.ts <<'TS'
export interface Order {
  id: string;
  buyerId: string;
  lines: { sku: string; quantity: number }[];
}
TS
cat >src/fulfillment/label.ts <<'TS'
export interface ParcelLabel {
  carrier: string;
  trackingCode: string;
}
TS
cat >src/fulfillment/dispatch.ts <<'TS'
export function createParcelFor(orderIds: string[]): string {
  return orderIds.join(",");
}
TS
cat >src/fulfillment/split.py <<'PY'
def split_parcel_lines(lines):
    return [lines[i:i + 10] for i in range(0, len(lines), 10)]
PY
