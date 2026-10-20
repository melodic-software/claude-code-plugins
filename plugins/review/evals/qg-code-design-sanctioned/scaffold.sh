#!/usr/bin/env bash
# main holds a payments service whose README declares src/handlers/index.js the handler registry. The
# branch adds a refund handler plus its registry entry, and moves src/util/money.js to src/lib/money.js
# unchanged, updating the one import. Neither is an introduced copy. The base commit SHA is in
# .review-base.
set -euo pipefail

git init -q -b main
git config user.name eval
git config user.email eval@example.invalid
printf '.review-base\n' >>.git/info/exclude
mkdir -p src/handlers src/util

cat >README.md <<'MD'
# payments

`src/handlers/index.js` is the handler registry: it lists every handler once, by name. A new
handler adds its file under `src/handlers/` and one line to the registry.
MD

cat >src/util/money.js <<'JS'
export function toCents(amount) {
  return Math.round(amount * 100);
}

export function fromCents(cents) {
  return cents / 100;
}
JS

cat >src/handlers/charge.js <<'JS'
import { toCents } from "../util/money.js";

export function charge(gateway, order) {
  return gateway.capture(order.id, toCents(order.total));
}
JS

cat >src/handlers/index.js <<'JS'
import { charge } from "./charge.js";

export const handlers = {
  charge,
};
JS

git add .
git commit -q -m "feat: charge handler"
git rev-parse HEAD >.review-base
git checkout -q -b feat/refunds

mkdir -p src/lib
git mv src/util/money.js src/lib/money.js
sed -i 's#\.\./util/money\.js#../lib/money.js#' src/handlers/charge.js

cat >src/handlers/refund.js <<'JS'
import { toCents } from "../lib/money.js";

export function refund(gateway, order, amount) {
  return gateway.refund(order.id, toCents(amount));
}
JS

cat >src/handlers/index.js <<'JS'
import { charge } from "./charge.js";
import { refund } from "./refund.js";

export const handlers = {
  charge,
  refund,
};
JS

git add -A src
git commit -q -m "feat: refund handler; move money helpers to src/lib"
