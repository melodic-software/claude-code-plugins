#!/usr/bin/env bash
set -euo pipefail

git init -q -b main
git config user.name eval
git config user.email eval@example.invalid
mkdir -p src

cat >src/money.js <<'JS'
export function formatPrice(cents, currency = "USD") {
  return new Intl.NumberFormat("en-US", { style: "currency", currency }).format(cents / 100);
}
JS

cat >src/cart.js <<'JS'
import { formatPrice } from "./money.js";

export function cartTotalLine(cart) {
  const cents = cart.items.reduce((sum, item) => sum + item.cents * item.qty, 0);
  return `Total: ${formatPrice(cents, cart.currency)}`;
}
JS

cat >src/receipt.js <<'JS'
import { formatPrice } from "./money.js";

export function receiptLine(item) {
  return `${item.name} x${item.qty}: ${formatPrice(item.cents * item.qty)}`;
}
JS

cat >package.json <<'JSON'
{ "name": "storefront", "type": "module", "private": true }
JSON

git add .
git commit -q -m "feat: cart and receipt lines"

git checkout -q -b feat/invoice-line
cat >src/invoice.js <<'JS'
export function invoiceLine(invoice) {
  const dollars = (invoice.cents / 100).toFixed(2);
  return `Invoice ${invoice.id}: $${dollars}`;
}
JS

git add .
git commit -q -m "feat(invoice): add the invoice line"

mkdir -p .claude-lane
git diff main...HEAD >.claude-lane/pr.diff
