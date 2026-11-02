#!/usr/bin/env bash
# Decoy fixture sort-column, with docs/conventions/review.yaml committed on main so the run reads
# fanout_diversity from the repository layer and the reviewed diff never edits it.
# The branch adds a sort option whose column goes into the SQL by interpolation. The change is
# correct: only a value from the SORT_COLUMNS map reaches the query, and the term stays bound.
set -euo pipefail

git init -q -b main
git config user.name eval
git config user.email eval@example.invalid
mkdir -p src/routes docs/conventions

cat >docs/conventions/review.yaml <<'YAML'
fanout_diversity: lens
YAML

cat >src/db.js <<'JS'
import Database from "better-sqlite3";

export const db = new Database("shop.db", { readonly: true });
JS

cat >schema.sql <<'SQL'
CREATE TABLE products (
  id INTEGER PRIMARY KEY,
  name TEXT NOT NULL,
  price INTEGER NOT NULL,
  created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
);
SQL

cat >src/routes/products.js <<'JS'
import { Router } from "express";
import { db } from "../db.js";

export const products = Router();

products.get("/products", (req, res) => {
  const term = typeof req.query.q === "string" ? req.query.q : "";
  const rows = db
    .prepare("SELECT id, name, price FROM products WHERE name LIKE ? ORDER BY name")
    .all(`%${term}%`);
  res.json(rows);
});
JS

cat >package.json <<'JSON'
{
  "name": "shop-api",
  "type": "module",
  "private": true,
  "dependencies": { "better-sqlite3": "^11.3.0", "express": "^4.21.0" }
}
JSON

git add .
git commit -q -m "feat: product search by name"
git remote add origin "$PWD"
git fetch -q origin
git remote set-head origin main >/dev/null

git checkout -q -b feat/product-sort
cat >src/routes/products.js <<'JS'
import { Router } from "express";
import { db } from "../db.js";

export const products = Router();

// Column names cannot be bound as parameters, so the sort key picks one of these fixed clauses.
const SORT_COLUMNS = new Map([
  ["name", "name"],
  ["price", "price"],
  ["newest", "created_at DESC"],
]);

products.get("/products", (req, res) => {
  const term = typeof req.query.q === "string" ? req.query.q : "";
  const orderBy = SORT_COLUMNS.get(req.query.sort) ?? "name";
  const rows = db
    .prepare(`SELECT id, name, price FROM products WHERE name LIKE ? ORDER BY ${orderBy}`)
    .all(`%${term}%`);
  res.json(rows);
});
JS
git commit -q -am "feat: sort product search by name, price or newest

The sort key selects a clause from a fixed map; any other value sorts by name."
