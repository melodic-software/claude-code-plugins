#!/usr/bin/env bash
# Seed the one file the scan targets.
set -euo pipefail

mkdir -p src
cat >src/discount.js <<'JS'
// Discount for an order, by its total in cents.
// Orders of 10000 cents ($100.00) or more get 10% off; 5000 cents or more get 5% off.
export function discountRate(totalCents) {
  if (totalCents > 10000) return 0.1;
  if (totalCents >= 5000) return 0.05;
  return 0;
}

// Total after the discount, rounded to whole cents.
export function applyDiscount(totalCents) {
  return totalCents - Math.round(totalCents * discountRate(totalCents));
}
JS
