#!/usr/bin/env bash
# New scaffold for the reviewer-diversity eval, with docs/conventions/review.yaml committed on main
# so the run reads fanout_diversity from the repository layer and the reviewed diff never edits it.
# The branch makes store settings per tenant but keeps the process-wide cache key "settings", so
# the first tenant's settings are served to every tenant until the unchanged cache's entry expires.
set -euo pipefail

git init -q -b main
git config user.name eval
git config user.email eval@example.invalid
mkdir -p src/routes src/middleware test docs/conventions

cat >docs/conventions/review.yaml <<'YAML'
fanout_diversity: lens
YAML

cat >src/cache.js <<'JS'
// Process-wide memo shared by every request: the first loader result for a key is kept for ten
// minutes, whoever asked for it.
const store = new Map();
const TTL_MS = 10 * 60 * 1000;

export async function cached(key, loader) {
  const hit = store.get(key);
  if (hit && Date.now() - hit.at < TTL_MS) {
    return hit.value;
  }
  const value = await loader();
  store.set(key, { value, at: Date.now() });
  return value;
}

export function clearCache() {
  store.clear();
}
JS

cat >src/db.js <<'JS'
import Database from "better-sqlite3";

export const db = new Database(process.env.DB_PATH || "shop.db");

db.exec(`
  CREATE TABLE IF NOT EXISTS orders (
    id INTEGER PRIMARY KEY,
    total_cents INTEGER NOT NULL
  );
`);
JS

cat >src/settings.js <<'JS'
import { cached } from "./cache.js";

const DEFAULTS = { currency: "USD", locale: "en-US", taxInclusive: false };

export async function getSettings() {
  return cached("settings", async () => ({ ...DEFAULTS }));
}
JS

cat >src/routes/checkout.js <<'JS'
import { Router } from "express";
import { getSettings } from "../settings.js";

export const checkout = Router();

checkout.get("/checkout/summary", async (req, res) => {
  const settings = await getSettings();
  const total = Number(req.query.total_cents || 0);
  res.json({
    total: new Intl.NumberFormat(settings.locale, {
      style: "currency",
      currency: settings.currency,
    }).format(total / 100),
    taxInclusive: settings.taxInclusive,
  });
});
JS

cat >src/app.js <<'JS'
import express from "express";
import { checkout } from "./routes/checkout.js";

export const app = express();
app.use(checkout);
JS

cat >package.json <<'JSON'
{
  "name": "storefront",
  "type": "module",
  "private": true,
  "scripts": { "test": "node --test" },
  "dependencies": { "better-sqlite3": "^11.0.0", "express": "^4.19.0" }
}
JSON

git add .
git commit -q -m "feat: checkout summary in the store's currency"
git remote add origin "$PWD"
git fetch -q origin
git remote set-head origin main >/dev/null

git checkout -q -b feat/tenant-settings

cat >src/db.js <<'JS'
import Database from "better-sqlite3";

export const db = new Database(process.env.DB_PATH || "shop.db");

db.exec(`
  CREATE TABLE IF NOT EXISTS orders (
    id INTEGER PRIMARY KEY,
    tenant_id TEXT NOT NULL DEFAULT 'default',
    total_cents INTEGER NOT NULL
  );
  CREATE TABLE IF NOT EXISTS tenants (
    id TEXT PRIMARY KEY,
    host TEXT NOT NULL UNIQUE
  );
  CREATE TABLE IF NOT EXISTS tenant_settings (
    tenant_id TEXT PRIMARY KEY REFERENCES tenants(id),
    currency TEXT NOT NULL,
    locale TEXT NOT NULL,
    tax_inclusive INTEGER NOT NULL DEFAULT 0
  );
`);
JS

cat >src/middleware/tenant.js <<'JS'
import { db } from "../db.js";

const byHost = db.prepare("SELECT id FROM tenants WHERE host = ?");

// Every storefront is served from its own host name; an unknown host gets a 404.
export function resolveTenant(req, res, next) {
  const host = String(req.hostname || "").toLowerCase();
  const row = byHost.get(host);
  if (!row) {
    return res.status(404).json({ error: "unknown store" });
  }
  req.tenant = { id: row.id };
  next();
}
JS

cat >src/settings.js <<'JS'
import { db } from "./db.js";
import { cached } from "./cache.js";

const DEFAULTS = { currency: "USD", locale: "en-US", taxInclusive: false };

const byTenant = db.prepare(
  "SELECT currency, locale, tax_inclusive FROM tenant_settings WHERE tenant_id = ?",
);

export async function getSettings(tenantId) {
  if (!tenantId) {
    throw new Error("getSettings needs a tenant id");
  }
  return cached("settings", async () => {
    const row = byTenant.get(tenantId);
    if (!row) {
      return { ...DEFAULTS };
    }
    return {
      currency: row.currency,
      locale: row.locale,
      taxInclusive: row.tax_inclusive === 1,
    };
  });
}
JS

cat >src/routes/checkout.js <<'JS'
import { Router } from "express";
import { getSettings } from "../settings.js";

export const checkout = Router();

checkout.get("/checkout/summary", async (req, res) => {
  const settings = await getSettings(req.tenant.id);
  const total = Number(req.query.total_cents || 0);
  if (!Number.isInteger(total) || total < 0) {
    return res.status(400).json({ error: "total_cents must be a whole number of cents" });
  }
  res.json({
    total: new Intl.NumberFormat(settings.locale, {
      style: "currency",
      currency: settings.currency,
    }).format(total / 100),
    taxInclusive: settings.taxInclusive,
  });
});
JS

cat >src/app.js <<'JS'
import express from "express";
import { resolveTenant } from "./middleware/tenant.js";
import { checkout } from "./routes/checkout.js";

export const app = express();
app.set("trust proxy", true);
app.use(resolveTenant);
app.use(checkout);
JS

cat >test/settings.test.js <<'JS'
import { test, beforeEach } from "node:test";
import assert from "node:assert/strict";
import { db } from "../src/db.js";
import { clearCache } from "../src/cache.js";
import { getSettings } from "../src/settings.js";

beforeEach(() => {
  clearCache();
  db.exec("DELETE FROM tenant_settings; DELETE FROM tenants;");
  db.exec("INSERT INTO tenants (id, host) VALUES ('eu', 'eu.example.test')");
  db.exec(
    "INSERT INTO tenant_settings (tenant_id, currency, locale, tax_inclusive) VALUES ('eu', 'EUR', 'de-DE', 1)",
  );
});

test("a tenant with settings gets its own currency and tax rule", async () => {
  assert.deepEqual(await getSettings("eu"), {
    currency: "EUR",
    locale: "de-DE",
    taxInclusive: true,
  });
});

test("a tenant without a settings row gets the defaults", async () => {
  assert.equal((await getSettings("new-store")).currency, "USD");
});

test("a missing tenant id is an error", async () => {
  await assert.rejects(() => getSettings(undefined));
});
JS

git add .
git commit -q -m "feat: per-tenant store settings

Each storefront host resolves to its tenant, and checkout formats totals
with that tenant's own currency, locale and tax rule from tenant_settings."
