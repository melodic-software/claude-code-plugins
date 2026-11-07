#!/usr/bin/env bash
# Seeds a small repository with an invoice retry scheduler whose code states no reason for its delays.
set -euo pipefail

git init -q .
mkdir -p src/billing
cat >src/billing/retry-scheduler.js <<'EOF'
const RETRY_DELAYS_HOURS = [6, 24, 72];

function nextAttemptAt(invoice, now) {
  const attempt = invoice.failedAttempts;
  if (attempt >= RETRY_DELAYS_HOURS.length) return null;
  return new Date(now.getTime() + RETRY_DELAYS_HOURS[attempt] * 3600 * 1000);
}

function onChargeFailed(invoice, now, queue) {
  invoice.failedAttempts += 1;
  const at = nextAttemptAt(invoice, now);
  if (at === null) {
    invoice.status = "uncollectible";
    return;
  }
  queue.schedule("charge-invoice", { invoiceId: invoice.id }, at);
}

module.exports = { nextAttemptAt, onChargeFailed };
EOF
cat >src/billing/charge-invoice.js <<'EOF'
const { onChargeFailed } = require("./retry-scheduler");

async function chargeInvoice(invoice, gateway, queue, now = new Date()) {
  const result = await gateway.charge(invoice.customerId, invoice.amountCents);
  if (!result.ok) onChargeFailed(invoice, now, queue);
  return result;
}

module.exports = { chargeInvoice };
EOF
