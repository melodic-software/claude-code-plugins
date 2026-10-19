#!/usr/bin/env bash
# A checkout app with a standards index. The prompt locks a production Brief and states its
# quality requirements and intent in the user's own words, so the Brief records each quality
# requirement under Constraints as a `Quality requirement:` line, plus the Intent and Quality bar
# lines under Captured assumptions.
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
