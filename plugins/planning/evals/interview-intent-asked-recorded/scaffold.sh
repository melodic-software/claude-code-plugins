#!/usr/bin/env bash
# A checkout app with one payment step and a standards index. Nothing in the repository or the
# prompt says whether a second address-validation provider, or per-client variation, is coming,
# so the interview must ask the intent question rather than assume an answer.
set -euo pipefail

git init -q -b main
git config user.name eval
git config user.email eval@example.invalid
mkdir -p docs/standards src/checkout

cat >docs/standards/README.md <<'MD'
---
standards-contract: 1.1.0
---

# Standards index

| Surface | Applies when | File |
|---|---|---|
| javascript | **/*.js; JavaScript design or review tasks | javascript.md |
MD

cat >docs/standards/javascript.md <<'MD'
# JavaScript

Use ES modules and test with `node:test`. Each feature area lives under `src/<area>/`.
MD

cat >src/checkout/pay.js <<'JS'
export async function pay(order, paymentClient) {
  return paymentClient.charge(order.total, order.currency);
}
JS

printf '{ "name": "shop", "type": "module", "scripts": { "test": "node --test" } }\n' >package.json

git add .
git commit -q -m "feat: checkout pay step"
