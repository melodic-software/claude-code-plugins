#!/usr/bin/env bash
# Writes a Northwind Trading repository with one bounded context and its glossary at docs/glossary.md,
# in the bold-term, definition, Avoid-line shape.
set -euo pipefail
mkdir -p docs src/orders
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

Avoid: parcel, order line
MD
cat >src/orders/order.ts <<'TS'
export interface Order {
  id: string;
  buyerId: string;
  lines: { sku: string; quantity: number }[];
}
TS
