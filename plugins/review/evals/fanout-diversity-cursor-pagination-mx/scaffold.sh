#!/usr/bin/env bash
# New scaffold for the reviewer-diversity eval, with docs/conventions/review.yaml committed on main
# so the run reads fanout_diversity from the repository layer and the reviewed diff never edits it.
# The branch replaces offset paging with a cursor and claims every product is visited exactly once,
# but it orders each page by name while the cursor filters on id, so products whose id is below the
# last id of a page but whose name sorts later are never returned.
set -euo pipefail

git init -q -b main
git config user.name eval
git config user.email eval@example.invalid
mkdir -p src/routes src/client docs/conventions

cat >docs/conventions/review.yaml <<'YAML'
fanout_diversity: model
YAML

cat >src/db.js <<'JS'
import Database from "better-sqlite3";

export const db = new Database(process.env.DB_PATH || "shop.db");

db.exec(`
  CREATE TABLE IF NOT EXISTS products (
    id INTEGER PRIMARY KEY,
    name TEXT NOT NULL,
    price INTEGER NOT NULL,
    archived INTEGER NOT NULL DEFAULT 0
  );
`);
JS

cat >src/routes/catalog.js <<'JS'
import { Router } from "express";
import { db } from "../db.js";

export const catalog = Router();

catalog.get("/catalog", (req, res) => {
  const page = Math.max(0, Number(req.query.page) || 0);
  const rows = db
    .prepare("SELECT id, name, price FROM products WHERE archived = 0 ORDER BY name LIMIT 20 OFFSET ?")
    .all(page * 20);
  res.json({ items: rows, page });
});
JS

cat >src/client/catalog.js <<'JS'
// Used by the nightly feed export: walks the whole catalogue a page at a time.
export async function allProducts(fetchJson) {
  const out = [];
  for (let page = 0; ; page += 1) {
    const { items } = await fetchJson(`/catalog?page=${page}`);
    out.push(...items);
    if (items.length < 20) {
      return out;
    }
  }
}
JS

cat >package.json <<'JSON'
{
  "name": "storefront-catalog",
  "type": "module",
  "private": true,
  "dependencies": { "better-sqlite3": "^11.0.0", "express": "^4.19.0" }
}
JSON

git add .
git commit -q -m "feat: paged catalogue listing in name order"
git remote add origin "$PWD"
git fetch -q origin
git remote set-head origin main >/dev/null

git checkout -q -b feat/catalog-cursor

cat >src/cursor.js <<'JS'
// Opaque cursors: base64url of a small JSON object, so clients cannot depend on the format.
export function encodeCursor(value) {
  return Buffer.from(JSON.stringify(value)).toString("base64url");
}

export function decodeCursor(text) {
  if (!text) {
    return null;
  }
  try {
    return JSON.parse(Buffer.from(String(text), "base64url").toString("utf8"));
  } catch {
    return null;
  }
}
JS

cat >src/routes/catalog.js <<'JS'
import { Router } from "express";
import { db } from "../db.js";
import { decodeCursor, encodeCursor } from "../cursor.js";

export const catalog = Router();

const DEFAULT_LIMIT = 20;
const MAX_LIMIT = 100;

const pageQuery = db.prepare(
  "SELECT id, name, price FROM products WHERE archived = 0 AND id > ? ORDER BY name LIMIT ?",
);

function clampLimit(raw) {
  const n = Number.parseInt(raw, 10);
  if (!Number.isFinite(n) || n < 1) {
    return DEFAULT_LIMIT;
  }
  return Math.min(n, MAX_LIMIT);
}

catalog.get("/catalog", (req, res) => {
  const limit = clampLimit(req.query.limit);
  const cursor = decodeCursor(req.query.after);
  if (req.query.after && !cursor) {
    return res.status(400).json({ error: "bad cursor" });
  }
  const afterId = cursor ? cursor.id : 0;
  const items = pageQuery.all(afterId, limit);
  const last = items[items.length - 1];
  res.json({
    items,
    next: items.length === limit ? encodeCursor({ id: last.id }) : null,
  });
});
JS

cat >src/client/catalog.js <<'JS'
// Used by the nightly feed export: walks the whole catalogue a page at a time.
export async function allProducts(fetchJson) {
  const out = [];
  let after = null;
  do {
    const query = after ? `?limit=100&after=${encodeURIComponent(after)}` : "?limit=100";
    const { items, next } = await fetchJson(`/catalog${query}`);
    out.push(...items);
    after = next;
  } while (after);
  return out;
}
JS

git add .
git commit -q -m "feat: page through the catalogue with a cursor

Offset paging skipped or repeated products when one was added or archived
between two page requests. Each page now carries a cursor, so the nightly
feed export visits every product exactly once, still in name order."
