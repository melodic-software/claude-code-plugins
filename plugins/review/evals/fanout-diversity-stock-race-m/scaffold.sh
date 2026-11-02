#!/usr/bin/env bash
# New scaffold for the reviewer-diversity eval, with docs/conventions/review.yaml committed on main
# so the run reads fanout_diversity from the repository layer and the reviewed diff never edits it.
# On main, reserve checks and writes the stock level with no await between them; the branch awaits
# the warehouse between the read and the write, so two concurrent checkouts can sell one unit twice.
set -euo pipefail

git init -q -b main
git config user.name eval
git config user.email eval@example.invalid
mkdir -p src docs/conventions

cat >docs/conventions/review.yaml <<'YAML'
fanout_diversity: model
YAML

cat >src/warehouse.js <<'JS'
// Each call is a network round trip to the warehouse service.
export async function confirmSku(sku) {
  const res = await fetch(`https://warehouse.example.invalid/skus/${encodeURIComponent(sku)}`);
  if (!res.ok) {
    throw new Error(`the warehouse does not stock ${sku}`);
  }
}

export async function recordReservation(sku, qty) {
  await fetch("https://warehouse.example.invalid/reservations", {
    method: "POST",
    body: JSON.stringify({ sku, qty }),
  });
}
JS

cat >src/inventory.js <<'JS'
import { recordReservation } from "./warehouse.js";

const stock = new Map();

export function setStock(sku, count) {
  stock.set(sku, count);
}

export async function reserve(sku, qty) {
  const available = stock.get(sku) ?? 0;
  if (available < qty) {
    throw new Error(`only ${available} of ${sku} left`);
  }
  stock.set(sku, available - qty);
  await recordReservation(sku, qty);
  return available - qty;
}
JS

cat >src/checkout.js <<'JS'
import { reserve } from "./inventory.js";

// The server runs checkout for many requests at once.
export async function checkout(cart) {
  for (const item of cart.items) {
    await reserve(item.sku, item.qty);
  }
  return { ok: true };
}
JS

cat >package.json <<'JSON'
{ "name": "storefront-inventory", "type": "module", "private": true }
JSON

git add .
git commit -q -m "feat: reserve stock at checkout"
git remote add origin "$PWD"
git fetch -q origin
git remote set-head origin main >/dev/null

git checkout -q -b feat/warehouse-confirm
cat >src/inventory.js <<'JS'
import { confirmSku, recordReservation } from "./warehouse.js";

const stock = new Map();

export function setStock(sku, count) {
  stock.set(sku, count);
}

export async function reserve(sku, qty) {
  const available = stock.get(sku) ?? 0;
  if (available < qty) {
    throw new Error(`only ${available} of ${sku} left`);
  }
  await confirmSku(sku);
  stock.set(sku, available - qty);
  await recordReservation(sku, qty);
  return available - qty;
}
JS
git commit -q -am "feat: confirm each SKU with the warehouse before reserving it

A SKU the warehouse no longer stocks now fails the reservation."
