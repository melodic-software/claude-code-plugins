#!/usr/bin/env bash
# A finished debug run: the pricing client's retry loop is capped and committed with its
# regression test, and the run notes hold the hypothesis table with verdicts and the red and
# green loop output. No post-mortem is written yet.
set -euo pipefail

git init -q -b main
git config user.name eval
git config user.email eval@example.invalid
mkdir -p src/pricing test notes

cat > src/pricing/client.js <<'JS'
async function quote(fetchPrice, order) {
  for (;;) {
    try {
      return await fetchPrice(order);
    } catch (error) {
      if (error.code !== "RATE_LIMITED") throw error;
    }
  }
}

module.exports = { quote };
JS

git add .
git commit -q -m "feat(pricing): quote orders through the pricing service"

cat > src/pricing/client.js <<'JS'
const MAX_ATTEMPTS = 3;

async function quote(fetchPrice, order) {
  for (let attempt = 1; ; attempt++) {
    try {
      return await fetchPrice(order);
    } catch (error) {
      if (error.code !== "RATE_LIMITED" || attempt >= MAX_ATTEMPTS) throw error;
    }
  }
}

module.exports = { quote, MAX_ATTEMPTS };
JS

cat > test/client.test.js <<'JS'
const test = require("node:test");
const assert = require("node:assert");
const { quote, MAX_ATTEMPTS } = require("../src/pricing/client");

test("a $1,200 order stops retrying after MAX_ATTEMPTS rate-limited calls", async () => {
  let calls = 0;
  const alwaysLimited = async () => {
    calls++;
    throw Object.assign(new Error("limited"), { code: "RATE_LIMITED" });
  };
  await assert.rejects(quote(alwaysLimited, { total: 1200 }), /limited/);
  assert.strictEqual(calls, MAX_ATTEMPTS);
});
JS

cat > notes/checkout-timeout.md <<'MD'
# Debug notes: checkout times out above $1k

Loop (a scratch script, deleted in cleanup): `node scripts/repro-checkout.js 1200` posts a $1,200 order against the stubbed pricing
service, which rate-limits every order over $1,000. Exit 1 = timeout reproduced.

Red run, before the fix:

    POST /checkout total=1200 -> no response after 30000 ms (pricing calls: 41213)
    exit 1

## Hypotheses

| Rank | Cause | Refuted if | Supported if | Verdict |
|---|---|---|---|---|
| 1 | Pricing client retries RATE_LIMITED with no bound | capping retries leaves the timeout | the pricing call count climbs without limit | confirmed: 41213 calls in one request |
| 2 | Payment gateway timeout is shorter for large orders | a $1,200 order with the gateway stubbed still times out | the stubbed run completes | refuted: still timed out with the gateway stubbed |
| 3 | Fraud check blocks orders over $1k | the fraud check disabled still times out | disabling it clears the timeout | refuted: fraud check returned in 12 ms |

Fix: cap attempts at 3 (`MAX_ATTEMPTS`) and surface the rate-limit error to checkout.

Green run, after the fix:

    POST /checkout total=1200 -> 503 pricing rate-limited after 3 attempts (412 ms)
    exit 0

Regression test: `test/client.test.js`.
MD

git add .
git commit -q -m "fix(pricing): cap rate-limit retries at 3 attempts

Checkout timed out for orders over \$1k: the pricing client retried
RATE_LIMITED with no bound. Regression test: test/client.test.js."
