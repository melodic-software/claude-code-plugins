#!/usr/bin/env bash
# New scaffold for the reviewer-diversity eval, with docs/conventions/review.yaml committed on main
# so the run reads fanout_diversity from the repository layer and the reviewed diff never edits it.
# On main, parsePrice returns dollars and both callers use dollars; the branch switches it to
# integer cents and updates cartTotal, but invoiceLine still reads the result as dollars.
set -euo pipefail

git init -q -b main
git config user.name eval
git config user.email eval@example.invalid
mkdir -p src docs/conventions

cat >docs/conventions/review.yaml <<'YAML'
fanout_diversity: lens
YAML

cat >src/price.js <<'JS'
// Parses a price such as "12.34" into dollars.
export function parsePrice(text) {
  return Number.parseFloat(text);
}
JS

cat >src/cart.js <<'JS'
import { parsePrice } from "./price.js";

export function cartTotal(lines) {
  const total = lines.reduce((sum, line) => sum + parsePrice(line.price) * line.qty, 0);
  return total.toFixed(2);
}
JS

cat >src/invoice.js <<'JS'
import { parsePrice } from "./price.js";

export function invoiceLine(line) {
  const amount = parsePrice(line.price) * line.qty;
  return `${line.sku}  ${line.qty} x ${line.price}  $${amount.toFixed(2)}`;
}
JS

cat >package.json <<'JSON'
{ "name": "storefront-pricing", "type": "module", "private": true }
JSON

git add .
git commit -q -m "feat: cart totals and invoice lines"
git remote add origin "$PWD"
git fetch -q origin
git remote set-head origin main >/dev/null

git checkout -q -b refactor/price-cents
cat >src/price.js <<'JS'
// Parses a price such as "12.34" into integer cents.
export function parsePrice(text) {
  return Math.round(Number.parseFloat(text) * 100);
}
JS
cat >src/cart.js <<'JS'
import { parsePrice } from "./price.js";

export function cartTotal(lines) {
  const cents = lines.reduce((sum, line) => sum + parsePrice(line.price) * line.qty, 0);
  return (cents / 100).toFixed(2);
}
JS
git commit -q -am "refactor: parsePrice returns integer cents

Float dollars rounded cart totals wrong. Every caller now works in cents."
