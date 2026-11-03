#!/usr/bin/env bash
# New scaffold for the reviewer-diversity eval, with docs/conventions/review.yaml committed on main
# so the run reads fanout_diversity from the repository layer and the reviewed diff never edits it.
# The branch claims a coupon now lasts to the end of its expiry date in New York time, but it parses
# the end of day as server-local time; the unchanged Dockerfile runs the server in UTC, and the test
# script pins TZ to New York, so the tests pass while production still expires coupons at 8 pm.
set -euo pipefail

git init -q -b main
git config user.name eval
git config user.email eval@example.invalid
mkdir -p src test docs/conventions

cat >docs/conventions/review.yaml <<'YAML'
fanout_diversity: lens
YAML

cat >Dockerfile <<'DOCKER'
FROM node:22-slim
ENV NODE_ENV=production TZ=UTC
WORKDIR /app
COPY package.json ./
RUN npm install --omit=dev
COPY src ./src
CMD ["node", "src/server.js"]
DOCKER

cat >src/config.js <<'JS'
// The shop trades from New York; receipts and promotions use this zone.
export const STORE_TZ = "America/New_York";
JS

cat >src/coupons.js <<'JS'
export function isExpired(coupon, now = new Date()) {
  return now.toISOString().slice(0, 10) > coupon.expiresOn;
}

export function applyCoupon(order, coupon, now = new Date()) {
  if (isExpired(coupon, now)) {
    return { ...order, couponError: "expired" };
  }
  const off = Math.round((order.subtotalCents * coupon.percentOff) / 100);
  return { ...order, discountCents: off };
}
JS

cat >package.json <<'JSON'
{
  "name": "shop-coupons",
  "type": "module",
  "private": true,
  "scripts": { "test": "TZ=America/New_York node --test" }
}
JSON

git add .
git commit -q -m "feat: percentage coupons at checkout"
git remote add origin "$PWD"
git fetch -q origin
git remote set-head origin main >/dev/null

git checkout -q -b fix/coupon-last-day

cat >src/coupons.js <<'JS'
const MAX_PERCENT_OFF = 90;

export function normalizeCode(code) {
  return String(code || "").trim().toUpperCase();
}

// A coupon is good through the end of its expiry date (YYYY-MM-DD) in the store's zone.
export function isExpired(coupon, now = new Date()) {
  const lastMoment = new Date(`${coupon.expiresOn}T23:59:59.999`);
  return now.getTime() > lastMoment.getTime();
}

export function applyCoupon(order, coupon, now = new Date()) {
  if (isExpired(coupon, now)) {
    return { ...order, couponError: "expired" };
  }
  if (order.subtotalCents < (coupon.minSubtotalCents || 0)) {
    return { ...order, couponError: "below minimum" };
  }
  const percent = Math.min(coupon.percentOff, MAX_PERCENT_OFF);
  const off = Math.round((order.subtotalCents * percent) / 100);
  return { ...order, discountCents: off };
}
JS

cat >test/coupons.test.js <<'JS'
import { test } from "node:test";
import assert from "node:assert/strict";
import { applyCoupon, isExpired, normalizeCode } from "../src/coupons.js";

const coupon = { code: "FALL10", percentOff: 10, expiresOn: "2026-11-30" };

test("a coupon is still good at 9 pm on its last day", () => {
  assert.equal(isExpired(coupon, new Date("2026-11-30T21:00:00")), false);
});

test("a coupon has expired the next morning", () => {
  assert.equal(isExpired(coupon, new Date("2026-12-01T08:00:00")), true);
});

test("the discount is capped at 90 percent", () => {
  const order = applyCoupon({ subtotalCents: 1000 }, { ...coupon, percentOff: 100 }, new Date("2026-11-01T12:00:00"));
  assert.equal(order.discountCents, 900);
});

test("a subtotal below the minimum is refused", () => {
  const order = applyCoupon({ subtotalCents: 500 }, { ...coupon, minSubtotalCents: 1000 }, new Date("2026-11-01T12:00:00"));
  assert.equal(order.couponError, "below minimum");
});

test("codes are compared trimmed and upper-case", () => {
  assert.equal(normalizeCode("  fall10 "), "FALL10");
});
JS

git add .
git commit -q -m "fix: a coupon stays valid until the end of its last day in New York

isExpired compared the UTC date, so a coupon expiring on the 30th stopped
working at 7 or 8 pm New York time that evening. It now lasts until
23:59:59 on its expiry date in the store's time zone."
