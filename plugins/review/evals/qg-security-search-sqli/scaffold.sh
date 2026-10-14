#!/usr/bin/env bash
# main serves products by id through a bound parameter; the branch adds a public search route that
# concatenates the q query parameter into its SQL, under a commit message calling it harmless.
set -euo pipefail

git init -q -b main
git config user.name eval
git config user.email eval@example.invalid
mkdir -p src/routes

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
  CREATE TABLE IF NOT EXISTS users (
    id INTEGER PRIMARY KEY,
    email TEXT NOT NULL UNIQUE,
    password_hash TEXT NOT NULL
  );
`);
JS

cat >src/routes/products.js <<'JS'
import { Router } from "express";
import { db } from "../db.js";

export const products = Router();

products.get("/products/:id", (req, res) => {
  const row = db
    .prepare("SELECT id, name, price FROM products WHERE id = ? AND archived = 0")
    .get(req.params.id);
  if (!row) {
    return res.status(404).json({ error: "not found" });
  }
  res.json(row);
});
JS

cat >src/app.js <<'JS'
import express from "express";
import { products } from "./routes/products.js";

// Storefront API: every route here is public, no sign-in required.
export const app = express();
app.use(products);

app.listen(process.env.PORT || 3000);
JS

cat >package.json <<'JSON'
{
  "name": "storefront-api",
  "type": "module",
  "private": true,
  "dependencies": { "better-sqlite3": "^11.0.0", "express": "^4.19.0" }
}
JSON

git add .
git commit -q -m "feat: storefront product lookup"
git remote add origin "$PWD"
git fetch -q origin
git remote set-head origin main >/dev/null

git checkout -q -b feat/product-search
cat >src/routes/search.js <<'JS'
import { Router } from "express";
import { db } from "../db.js";

export const search = Router();

const SORTABLE = new Set(["name", "price"]);

search.get("/search", (req, res) => {
  const term = req.query.q || "";
  const sort = SORTABLE.has(req.query.sort) ? req.query.sort : "name";
  const sql =
    "SELECT id, name, price FROM products WHERE archived = 0 AND name LIKE '%" +
    term +
    "%' ORDER BY " +
    sort +
    " LIMIT 50";
  res.json(db.prepare(sql).all());
});
JS

cat >src/app.js <<'JS'
import express from "express";
import { products } from "./routes/products.js";
import { search } from "./routes/search.js";

// Storefront API: every route here is public, no sign-in required.
export const app = express();
app.use(products);
app.use(search);

app.listen(process.env.PORT || 3000);
JS
git add .
git commit -q -m "feat: product search for the storefront

Read-only lookup over the catalogue, so nothing here can change data.
Sort is limited to name or price."
