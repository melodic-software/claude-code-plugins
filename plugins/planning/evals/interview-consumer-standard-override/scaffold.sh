#!/usr/bin/env bash
# A checkout app whose standards index routes integration work to integrations.md. That file says
# every external service goes behind an interface from its first implementation, with no wait for a
# second provider. The bundled reuse default waits for real repetition when a second variant is
# speculative, so the consumer standard wins and the Brief names the default it overrode.
set -euo pipefail

git init -q -b main
git config user.name eval
git config user.email eval@example.invalid
mkdir -p docs/standards src/checkout src/integrations/ports

cat >docs/standards/README.md <<'MD'
---
standards-contract: 1.1.0
---

# Standards index

| Surface | Applies when | File |
|---|---|---|
| javascript | **/*.js; JavaScript design or review tasks | javascript.md |
| integrations | any external service integration, provider choice, or design of code under src/integrations/ | integrations.md |
MD

cat >docs/standards/javascript.md <<'MD'
# JavaScript

Use ES modules and test with `node:test`. Each feature area lives under `src/<area>/`.
MD

cat >docs/standards/integrations.md <<'MD'
# Integrations

Every external service sits behind an interface in `src/integrations/ports/` from its first
implementation, with the vendor client as one adapter beside it. Do not wait for a second provider
before adding the interface: our clients swap vendors per contract.
MD

cat >src/integrations/ports/payment-gateway.js <<'JS'
/** @typedef {{ charge(amount: number, currency: string): Promise<{ id: string }> }} PaymentGateway */
export {};
JS

cat >src/checkout/pay.js <<'JS'
/** @param {import('../integrations/ports/payment-gateway.js').PaymentGateway} gateway */
export async function pay(order, gateway) {
  return gateway.charge(order.total, order.currency);
}
JS

printf '{ "name": "shop", "type": "module", "scripts": { "test": "node --test" } }\n' >package.json

git add .
git commit -q -m "feat: checkout pay step behind a payment gateway port"
