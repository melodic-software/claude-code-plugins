#!/usr/bin/env bash
# Seed a small JavaScript repo where calcTotal is defined once and referenced from three other files.
set -euo pipefail

mkdir -p src/cart src/billing test
cat >src/cart/total.js <<'JS'
// Sums the line items, applies the coupon, then adds sales tax.
export function calcTotal(items, coupon, taxRate) {
  const subtotal = items.reduce((sum, item) => sum + item.priceCents * item.qty, 0);
  const discounted = coupon ? Math.max(0, subtotal - coupon.amountCents) : subtotal;
  return Math.round(discounted * (1 + taxRate));
}
JS
cat >src/cart/cart.js <<'JS'
import { calcTotal } from "./total.js";

export function cartSummary(cart) {
  return { lines: cart.items.length, totalCents: calcTotal(cart.items, cart.coupon, cart.taxRate) };
}

export function previewTotal(cart) {
  return calcTotal(cart.items, null, cart.taxRate);
}
JS
cat >src/billing/invoice.js <<'JS'
import { calcTotal } from "../cart/total.js";

export function invoiceAmount(order) {
  return calcTotal(order.items, order.coupon, order.taxRate);
}
JS
cat >test/total.test.js <<'JS'
import { calcTotal } from "../src/cart/total.js";

test("applies coupon before tax", () => {
  expect(calcTotal([{ priceCents: 1000, qty: 1 }], { amountCents: 200 }, 0.1)).toBe(880);
});

test("no coupon", () => {
  expect(calcTotal([{ priceCents: 500, qty: 2 }], null, 0)).toBe(1000);
});
JS
