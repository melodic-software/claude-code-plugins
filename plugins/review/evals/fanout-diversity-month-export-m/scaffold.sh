#!/usr/bin/env bash
# New scaffold for the reviewer-diversity eval, with docs/conventions/review.yaml committed on main
# so the run reads fanout_diversity from the repository layer and the reviewed diff never edits it.
# Two defects against the commit's own claim (every order of the month, oldest first): the range
# ends at 00:00 on the month's last day, dropping that day's orders, and the sort comparator
# returns a boolean, so rows keep the database's order instead of being sorted.
set -euo pipefail

git init -q -b main
git config user.name eval
git config user.email eval@example.invalid
mkdir -p src/routes test docs/conventions

cat >docs/conventions/review.yaml <<'YAML'
fanout_diversity: model
YAML

cat >src/db.js <<'JS'
import Database from "better-sqlite3";

export const db = new Database(process.env.DB_PATH || "shop.db");

// created_at is an ISO 8601 UTC timestamp such as 2026-10-31T18:42:07.000Z. Orders imported from
// the old shop were inserted in batches, so row order does not follow created_at.
db.exec(`
  CREATE TABLE IF NOT EXISTS orders (
    id INTEGER PRIMARY KEY,
    total_cents INTEGER NOT NULL,
    created_at TEXT NOT NULL
  );
`);
JS

cat >src/app.js <<'JS'
import express from "express";

export const app = express();
JS

cat >package.json <<'JSON'
{
  "name": "shop-reports",
  "type": "module",
  "private": true,
  "scripts": { "test": "node --test" },
  "dependencies": { "better-sqlite3": "^11.0.0", "express": "^4.19.0" }
}
JSON

git add .
git commit -q -m "chore: orders table"
git remote add origin "$PWD"
git fetch -q origin
git remote set-head origin main >/dev/null

git checkout -q -b feat/month-export

cat >src/csv.js <<'JS'
function cell(value) {
  const text = value == null ? "" : String(value);
  return /[",\r\n]/.test(text) ? `"${text.replace(/"/g, '""')}"` : text;
}

export function toCsv(columns, rows) {
  const lines = [columns.map(cell).join(",")];
  for (const row of rows) {
    lines.push(columns.map((c) => cell(row[c])).join(","));
  }
  return `${lines.join("\r\n")}\r\n`;
}
JS

cat >src/export.js <<'JS'
import { db } from "./db.js";
import { toCsv } from "./csv.js";

const inRange = db.prepare(
  "SELECT id, total_cents, created_at FROM orders WHERE created_at >= ? AND created_at <= ?",
);

export function monthRange(year, month) {
  const start = new Date(Date.UTC(year, month - 1, 1));
  const end = new Date(Date.UTC(year, month, 0)); // last day of the month
  return { start: start.toISOString(), end: end.toISOString() };
}

export function exportMonth(year, month) {
  const { start, end } = monthRange(year, month);
  const rows = inRange.all(start, end);
  rows.sort((a, b) => a.created_at > b.created_at);
  return toCsv(["id", "total_cents", "created_at"], rows);
}
JS

cat >src/routes/export.js <<'JS'
import { Router } from "express";
import { exportMonth } from "../export.js";

export const exports = Router();

exports.get("/exports/orders/:year/:month.csv", (req, res) => {
  const year = Number(req.params.year);
  const month = Number(req.params.month);
  if (!Number.isInteger(year) || !Number.isInteger(month) || month < 1 || month > 12) {
    return res.status(400).json({ error: "year and month must be numbers, month 1 to 12" });
  }
  res.type("text/csv").send(exportMonth(year, month));
});
JS

cat >src/app.js <<'JS'
import express from "express";
import { exports } from "./routes/export.js";

export const app = express();
app.use(exports);
JS

cat >test/csv.test.js <<'JS'
import { test } from "node:test";
import assert from "node:assert/strict";
import { toCsv } from "../src/csv.js";
import { monthRange } from "../src/export.js";

test("cells with commas or quotes are quoted", () => {
  assert.equal(toCsv(["a"], [{ a: 'say "hi", then' }]), 'a\r\n"say ""hi"", then"\r\n');
});

test("the range starts on the first of the month", () => {
  assert.equal(monthRange(2026, 10).start, "2026-10-01T00:00:00.000Z");
});
JS

git add .
git commit -q -m "feat: monthly order export as CSV

GET /exports/orders/:year/:month.csv lists every order placed in that
calendar month (UTC), oldest first, for the accountant's import."
