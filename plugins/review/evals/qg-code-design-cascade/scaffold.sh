#!/usr/bin/env bash
# main holds a shop whose free-shipping threshold is FREE_SHIPPING_THRESHOLD in src/pricing.js. The
# branch adds a cart banner and a checkout summary that each hardcode the same 50 instead of importing
# it, and no test ties the copies together. The base commit SHA is in .review-base.
set -euo pipefail

git init -q -b main
git config user.name eval
git config user.email eval@example.invalid
printf '.review-base\n' >>.git/info/exclude
mkdir -p src/cart src/checkout

cat >src/pricing.js <<'JS'
export const FREE_SHIPPING_THRESHOLD = 50;
export const SHIPPING_FEE = 4.99;

export function shippingFor(subtotal) {
  return subtotal >= FREE_SHIPPING_THRESHOLD ? 0 : SHIPPING_FEE;
}
JS

cat >package.json <<'JSON'
{ "name": "shop", "type": "module", "private": true }
JSON

git add .
git commit -q -m "feat: shipping fee"
git rev-parse HEAD >.review-base
git checkout -q -b feat/cart-banner

cat >src/cart/banner.js <<'JS'
export function freeShippingBanner(subtotal) {
  const remaining = 50 - subtotal;
  if (remaining <= 0) {
    return "You get free shipping!";
  }
  return `Add $${remaining.toFixed(2)} more for free shipping on orders over $50.`;
}
JS

cat >src/checkout/summary.js <<'JS'
import { SHIPPING_FEE } from "../pricing.js";

export function summaryLines(subtotal) {
  const shipping = subtotal >= 50 ? 0 : SHIPPING_FEE;
  return [
    `Subtotal: $${subtotal.toFixed(2)}`,
    `Shipping: ${shipping === 0 ? "free" : "$" + shipping.toFixed(2)}`,
    `Total: $${(subtotal + shipping).toFixed(2)}`,
  ];
}
JS

git add src
git commit -q -m "feat: free-shipping banner and checkout summary"
