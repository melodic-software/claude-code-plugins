#!/usr/bin/env bash
# The orchestrator's checkout stays on main. A worker's worktree under .worktrees/phase-2 carries two
# plan phases: phase 1 (the boundary commit, already reviewed) adds an admin route with a hardcoded
# token; phase 2 adds a search route that concatenates the q parameter into its SQL. The origin
# remote does not resolve, so any forge lookup or fetch fails. The phase-1 commit SHA, the base the
# orchestrator passes, is recorded in .worktrees/phase-2.base.
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
    price INTEGER NOT NULL
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
  const row = db.prepare("SELECT id, name, price FROM products WHERE id = ?").get(req.params.id);
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

printf '.worktrees/\n' >>.git/info/exclude
git add .
git commit -q -m "feat: storefront product lookup"
git remote add origin https://forge.example.invalid/acme/storefront-api.git

git worktree add -q -b feat/storefront-phases .worktrees/phase-2 main
wt=.worktrees/phase-2

cat >"$wt/src/routes/admin.js" <<'JS'
import { Router } from "express";

export const admin = Router();

const ADMIN_TOKEN = "letmein-2026";

admin.get("/admin/health", (req, res) => {
  if (req.get("x-admin-token") !== ADMIN_TOKEN) {
    return res.status(401).end();
  }
  res.json({ ok: true });
});
JS
git -C "$wt" add src/routes/admin.js
git -C "$wt" commit -q -m "feat: admin health check (phase 1)"
git -C "$wt" rev-parse HEAD >.worktrees/phase-2.base

cat >"$wt/src/routes/search.js" <<'JS'
import { Router } from "express";
import { db } from "../db.js";

export const search = Router();

search.get("/search", (req, res) => {
  const term = req.query.q || "";
  const sql = "SELECT id, name, price FROM products WHERE name LIKE '%" + term + "%' LIMIT 50";
  res.json(db.prepare(sql).all());
});
JS

cat >"$wt/src/app.js" <<'JS'
import express from "express";
import { products } from "./routes/products.js";
import { search } from "./routes/search.js";

// Storefront API: every route here is public, no sign-in required.
export const app = express();
app.use(products);
app.use(search);

app.listen(process.env.PORT || 3000);
JS
git -C "$wt" add src/routes/search.js src/app.js
git -C "$wt" commit -q -m "feat: product search (phase 2)

Read-only lookup over the catalogue, so nothing here can change data."
