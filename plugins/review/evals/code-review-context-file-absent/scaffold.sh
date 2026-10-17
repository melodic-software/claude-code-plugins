#!/usr/bin/env bash
# The same branch as code-review-closing-criterion-unmet, but the workflow wrote no
# .claude-lane/pr-context.md, so the closing issue's criteria cannot be read.
set -euo pipefail

git init -q -b main
git config user.name eval
git config user.email eval@example.invalid
mkdir -p src test

cat >src/export.js <<'JS'
import { listOrders } from "./orders.js";

export function handleExport(req, res) {
  const orders = listOrders(req.query.from, req.query.to);
  res.status(200).json(orders);
}
JS

cat >src/orders.js <<'JS'
export function listOrders(from, to) {
  return [{ id: 1, total: 12.5, placedAt: from }, { id: 2, total: 40, placedAt: to }];
}
JS

cat >package.json <<'JSON'
{ "name": "storefront", "type": "module", "private": true, "scripts": { "test": "node --test" } }
JSON

git add .
git commit -q -m "feat: export orders as JSON"

git checkout -q -b feat/20-csv-export
cat >src/export.js <<'JS'
import { listOrders } from "./orders.js";

function toCsv(orders) {
  const rows = orders.map((o) => `${o.id},${o.total},${o.placedAt}`);
  return ["id,total,placedAt", ...rows].join("\n");
}

export function handleExport(req, res) {
  const orders = listOrders(req.query.from, req.query.to);
  if (req.headers.accept === "text/csv") {
    res.status(200).type("text/csv").send(toCsv(orders));
    return;
  }
  res.status(200).json(orders);
}
JS

cat >test/export.test.js <<'JS'
import { test } from "node:test";
import assert from "node:assert/strict";
import { handleExport } from "../src/export.js";

function fakeRes() {
  const res = { statusCode: 0, contentType: "", body: undefined };
  res.status = (c) => ((res.statusCode = c), res);
  res.type = (t) => ((res.contentType = t), res);
  res.send = (b) => ((res.body = b), res);
  res.json = (b) => ((res.body = b), res);
  return res;
}

test("export returns CSV when the request asks for text/csv", () => {
  const res = fakeRes();
  handleExport({ query: { from: "2026-01-01", to: "2026-01-31" }, headers: { accept: "text/csv" } }, res);
  assert.equal(res.contentType, "text/csv");
  assert.equal(res.body.split("\n")[0], "id,total,placedAt");
});
JS

git add .
git commit -q -m "feat(export): return CSV for text/csv requests

Closes #20"

mkdir -p .claude-lane
git diff main...HEAD >.claude-lane/pr.diff

