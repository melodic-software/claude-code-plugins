#!/usr/bin/env bash
# New scaffold for the reviewer-diversity eval, with docs/conventions/review.yaml committed on main
# so the run reads fanout_diversity from the repository layer and the reviewed diff never edits it.
# On main, countRows closes its file handle in a finally block; the branch drops the try/finally and
# throws on a wrong header before file.close(), so every bad upload leaks a handle.
set -euo pipefail

git init -q -b main
git config user.name eval
git config user.email eval@example.invalid
mkdir -p src docs/conventions

cat >docs/conventions/review.yaml <<'YAML'
fanout_diversity: lens
YAML

cat >src/import-csv.js <<'JS'
import { open } from "node:fs/promises";

export async function countRows(path) {
  const file = await open(path, "r");
  try {
    const text = await file.readFile("utf8");
    return text.split("\n").filter(Boolean).length - 1;
  } finally {
    await file.close();
  }
}
JS

cat >src/import-all.js <<'JS'
import { readdir } from "node:fs/promises";
import { join } from "node:path";
import { countRows } from "./import-csv.js";

// Runs nightly over every upload; one bad file must not stop the rest.
export async function importAll(dir) {
  const results = [];
  for (const name of await readdir(dir)) {
    try {
      results.push({ name, rows: await countRows(join(dir, name)) });
    } catch (error) {
      results.push({ name, error: error.message });
    }
  }
  return results;
}
JS

cat >package.json <<'JSON'
{ "name": "upload-import", "type": "module", "private": true }
JSON

git add .
git commit -q -m "feat: nightly import counts each upload's rows"
git remote add origin "$PWD"
git fetch -q origin
git remote set-head origin main >/dev/null

git checkout -q -b feat/csv-header-check
cat >src/import-csv.js <<'JS'
import { open } from "node:fs/promises";

const HEADER = "sku,qty,price";

export async function countRows(path) {
  const file = await open(path, "r");
  const text = (await file.readFile("utf8")).replace(/^﻿/, "");
  const [header, ...rows] = text.split(/\r?\n/).filter(Boolean);
  if (header !== HEADER) {
    throw new Error(`${path}: expected the header ${HEADER}`);
  }
  await file.close();
  return rows.length;
}
JS
git commit -q -am "feat: reject a CSV whose header is not sku,qty,price

A file with other columns now reports an error instead of a row count."
