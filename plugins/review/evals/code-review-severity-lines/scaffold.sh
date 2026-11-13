#!/usr/bin/env bash
# A small pull request with one correctness defect and no security or billing surface:
# the bulk discount its comment describes applies below the threshold instead of at or
# above it. A review of it has no CRITICAL finding, so its summary counts zero.
set -euo pipefail

git init -q -b main
git config user.name eval
git config user.email eval@example.invalid
mkdir -p src
cat >package.json <<'JSON'
{ "name": "storefront", "type": "module", "private": true, "scripts": { "test": "node --test" } }
JSON
cat >src/cart.js <<'JS'
// Cart arithmetic in integer cents.

export function lineTotalCents(line) {
  return line.unitPriceCents * line.quantity;
}

export function cartTotalCents(lines) {
  return lines.reduce((total, line) => total + lineTotalCents(line), 0);
}
JS
git add .
git commit -q -m "feat(cart): add cart totals"

git checkout -q -b feat/61-bulk-discount
cat >src/cart.js <<'JS'
// Cart arithmetic in integer cents.

// A line of BULK_THRESHOLD units or more gets BULK_PERCENT_OFF off its total.
export const BULK_THRESHOLD = 10;
export const BULK_PERCENT_OFF = 15;

export function lineTotalCents(line) {
  const gross = line.unitPriceCents * line.quantity;
  if (line.quantity < BULK_THRESHOLD) {
    return gross - Math.round((gross * BULK_PERCENT_OFF) / 100);
  }
  return gross;
}

export function cartTotalCents(lines) {
  return lines.reduce((total, line) => total + lineTotalCents(line), 0);
}
JS
git add .
git commit -q -m "feat(cart): give bulk lines a discount"

mkdir -p .claude-lane
git diff main...HEAD >.claude-lane/pr.diff
