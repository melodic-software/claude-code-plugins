#!/usr/bin/env bash
# Shared pull request for the explain-change cases. main applies coupons when an order is
# placed and stores the code on the order. The branch moves the coupon to the cart, and its
# migration drops orders.coupon_code, which loses every stored code: a revert of the merge
# commit does not bring the column's data back.
set -euo pipefail

git init -q -b main
git config user.name eval
git config user.email eval@example.invalid
mkdir -p src test migrations

cat >package.json <<'JSON'
{ "name": "storefront", "type": "module", "private": true, "scripts": { "test": "node --test" } }
JSON

cat >src/orders.js <<'JS'
import { db } from "./db.js";

export function placeOrder(cart, couponCode) {
  const discount = couponCode === "SPRING10" ? 0.1 : 0;
  const total = cart.subtotal * (1 - discount);
  return db.insert("orders", { total, coupon_code: couponCode ?? null });
}
JS

cat >src/db.js <<'JS'
export const db = { insert: (table, row) => ({ table, ...row }) };
JS

cat >migrations/0011_orders.sql <<'SQL'
CREATE TABLE orders (id SERIAL PRIMARY KEY, total NUMERIC NOT NULL, coupon_code TEXT);
SQL

git add .
git commit -q -m "feat: place orders with an optional coupon"
BASE=$(git rev-parse HEAD)

git checkout -q -b feat/76-coupon-at-cart
cat >src/cart.js <<'JS'
const COUPONS = { SPRING10: 0.1 };

export function applyCoupon(cart, code) {
  const rate = COUPONS[code];
  if (rate === undefined) return { ...cart, coupon: null };
  return { ...cart, coupon: code, subtotal: cart.subtotal * (1 - rate) };
}
JS

cat >src/orders.js <<'JS'
import { db } from "./db.js";

export function placeOrder(cart) {
  return db.insert("orders", { total: cart.subtotal });
}
JS

cat >migrations/0012_drop_orders_coupon_code.sql <<'SQL'
ALTER TABLE orders DROP COLUMN coupon_code;
SQL

cat >test/cart.test.js <<'JS'
import { test } from "node:test";
import assert from "node:assert/strict";
import { applyCoupon } from "../src/cart.js";

test("SPRING10 takes 10% off the cart", () => {
  assert.equal(applyCoupon({ subtotal: 100 }, "SPRING10").subtotal, 90);
});
JS

git add .
git commit -q -m "feat(cart): apply coupons at the cart

Closes #76"
HEAD_OID=$(git rev-parse HEAD)

mkdir -p .claude-lane/pr
git diff main...HEAD >.claude-lane/pr/pr.diff

cat >.claude-lane/pr/facts.json <<JSON
{
  "number": 77,
  "url": "https://github.com/acme/storefront/pull/77",
  "state": "OPEN",
  "isDraft": false,
  "title": "feat(cart): apply coupons at the cart",
  "body": "Closes #76\n\n## Summary\n\nCoupons now apply to the cart total before checkout, so the shopper sees the discount early. The order no longer stores the coupon code.\n\n## Verification\n\nnode --test passes.",
  "baseRefName": "main",
  "headRefName": "feat/76-coupon-at-cart",
  "baseRefOid": "$BASE",
  "headRefOid": "$HEAD_OID",
  "files": [
    { "path": "migrations/0012_drop_orders_coupon_code.sql", "additions": 1, "deletions": 0 },
    { "path": "src/cart.js", "additions": 7, "deletions": 0 },
    { "path": "src/orders.js", "additions": 2, "deletions": 4 },
    { "path": "test/cart.test.js", "additions": 7, "deletions": 0 }
  ],
  "labels": [],
  "visibility": "PUBLIC"
}
JSON
