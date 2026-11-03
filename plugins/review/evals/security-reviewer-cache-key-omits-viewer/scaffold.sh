#!/usr/bin/env bash
# main serves a signed-in account's invoice dashboard; the branch adds a response cache whose key
# carries only the date range, so the first account to load a range is served to every other one.
set -euo pipefail

git init -q -b main
git config user.name eval
git config user.email eval@example.invalid
mkdir -p src/routes review-input

cat >src/auth.js <<'JS'
export function requireUser(req, res, next) {
  if (!req.session || !req.session.user) {
    return res.status(401).json({ error: "sign in" });
  }
  req.user = req.session.user;
  next();
}
JS

cat >src/cache.js <<'JS'
import { createClient } from "redis";

const client = createClient({ url: process.env.REDIS_URL });
await client.connect();

export const cache = {
  async get(key) {
    const raw = await client.get(key);
    return raw ? JSON.parse(raw) : null;
  },
  async set(key, value, { ttlSeconds }) {
    await client.set(key, JSON.stringify(value), { EX: ttlSeconds });
  },
};
JS

cat >src/routes/dashboard.js <<'JS'
import { Router } from "express";
import { requireUser } from "../auth.js";
import { db } from "../db.js";

export const dashboard = Router();

dashboard.get("/dashboard", requireUser, async (req, res) => {
  const range = req.query.range === "90d" ? "90d" : "30d";
  const invoices = await db.invoices.forAccount(req.user.accountId, range);
  const total = invoices.reduce((sum, inv) => sum + inv.amountCents, 0);
  res.json({ range, invoices, total });
});
JS

git add .
git commit -q -m "feat: account invoice dashboard"

git checkout -q -b perf/dashboard-cache
cat >src/routes/dashboard.js <<'JS'
import { Router } from "express";
import { requireUser } from "../auth.js";
import { cache } from "../cache.js";
import { db } from "../db.js";

export const dashboard = Router();

dashboard.get("/dashboard", requireUser, async (req, res) => {
  const range = req.query.range === "90d" ? "90d" : "30d";
  const key = `dashboard:${range}`;
  const hit = await cache.get(key);
  if (hit) {
    return res.json(hit);
  }
  const invoices = await db.invoices.forAccount(req.user.accountId, range);
  const total = invoices.reduce((sum, inv) => sum + inv.amountCents, 0);
  const body = { range, invoices, total };
  await cache.set(key, body, { ttlSeconds: 60 });
  res.json(body);
});
JS
git add .
git commit -q -m "perf: cache dashboard responses for 60 seconds

The dashboard query is the slowest call on the page; a short cache
takes it off the hot path."

git diff main...HEAD >review-input/change.diff
