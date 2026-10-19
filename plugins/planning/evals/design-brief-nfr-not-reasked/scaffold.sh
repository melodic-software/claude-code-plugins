#!/usr/bin/env bash
# A checkout app and a production Brief whose Constraints already carry two quality requirements:
# the address lookup adds at most 300 ms at p95, and checkout proceeds when the provider is down.
# The design treats both as settled inputs and never asks for them again.
set -euo pipefail

git init -q -b main
git config user.name eval
git config user.email eval@example.invalid
mkdir -p src/checkout .work/address-validation

cat >src/checkout/pay.js <<'JS'
export async function pay(order, paymentClient) {
  return paymentClient.charge(order.total, order.currency);
}
JS

printf '{ "name": "shop", "type": "module", "scripts": { "test": "node --test" } }\n' >package.json

cat >.work/address-validation/PLAN.md <<'MD'
# Address validation

## Brief

### Goal
Checkout catches an undeliverable delivery address before payment, using the Loqate API.

### Constraints
- Loqate is the only address provider under contract.
- Quality requirement: performance: the address lookup barely slows checkout; target: adds at most 300 ms at p95
- Quality requirement: reliability: if Loqate is down or slower than 2 seconds, checkout proceeds and logs a warning
- Quality requirement: security: never log the full address

### Acceptance criteria
- An address Loqate marks undeliverable keeps the Pay button disabled and shows a message.

### Captured assumptions
- Quality bar: production
- Intent: second variant = speculative; existing structure: checkout has a pay step and no address check; upstream: none
MD

git add .
git commit -q -m "feat: checkout pay step"
