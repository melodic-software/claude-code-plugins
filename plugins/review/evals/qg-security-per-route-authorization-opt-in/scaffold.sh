#!/usr/bin/env bash
# main serves public product routes; the branch adds an admin router whose three routes each call
# the role check themselves. Every route has its check, so nothing is missing today: the defect is
# that authorization is opt-in per route, with no check on the router and no default deny.
set -euo pipefail

git init -q -b main
git config user.name eval
git config user.email eval@example.invalid
mkdir -p src/routes

cat >src/auth.js <<'JS'
export function currentUser(req) {
  return req.session?.user ?? null;
}

export function isAdmin(user) {
  return user?.role === "admin";
}
JS

cat >src/routes/products.js <<'JS'
import { Router } from "express";

export const products = Router();

products.get("/products", (_req, res) => {
  res.json([]);
});
JS

cat >src/app.js <<'JS'
import express from "express";
import { products } from "./routes/products.js";

export const app = express();
app.use(express.json());
app.use(products);

app.listen(process.env.PORT || 3000);
JS

cat >package.json <<'JSON'
{
  "name": "storefront-api",
  "type": "module",
  "private": true,
  "dependencies": { "express": "^4.19.0" }
}
JSON

git add .
git commit -q -m "feat: storefront products"
git remote add origin "$PWD"
git fetch -q origin
git remote set-head origin main >/dev/null

git checkout -q -b feat/admin-routes
cat >src/routes/admin.js <<'JS'
import { Router } from "express";
import { currentUser, isAdmin } from "../auth.js";
import { orders, refunds, users } from "../store.js";

export const admin = Router();

admin.get("/admin/orders", (req, res) => {
  if (!isAdmin(currentUser(req))) {
    return res.status(403).json({ error: "forbidden" });
  }
  res.json(orders.all());
});

admin.post("/admin/refunds", (req, res) => {
  if (!isAdmin(currentUser(req))) {
    return res.status(403).json({ error: "forbidden" });
  }
  res.status(201).json(refunds.create(req.body.orderId, req.body.amount));
});

admin.delete("/admin/users/:id", (req, res) => {
  if (!isAdmin(currentUser(req))) {
    return res.status(403).json({ error: "forbidden" });
  }
  users.remove(req.params.id);
  res.status(204).end();
});
JS

cat >src/store.js <<'JS'
export const orders = { all: () => [] };
export const refunds = { create: (orderId, amount) => ({ orderId, amount }) };
export const users = { remove: (_id) => undefined };
JS

cat >src/app.js <<'JS'
import express from "express";
import { admin } from "./routes/admin.js";
import { products } from "./routes/products.js";

export const app = express();
app.use(express.json());
app.use(products);
app.use(admin);

app.listen(process.env.PORT || 3000);
JS
git add .
git commit -q -m "feat: admin routes for orders, refunds and users

Each admin route checks the caller's role before doing anything."
