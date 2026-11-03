#!/usr/bin/env bash
# main lets a signed-in user request a CSV export under a name they choose; the branch adds a nightly
# job that deletes each expired export at a path built from that stored name, checked only for shape.
set -euo pipefail

git init -q -b main
git config user.name eval
git config user.email eval@example.invalid
mkdir -p src/routes src/jobs review-input

cat >src/routes/exports.js <<'JS'
import { Router } from "express";
import { requireUser } from "../auth.js";
import { db } from "../db.js";
import { queueExport } from "../export-worker.js";

export const exports = Router();

// The worker writes the CSV to path.join(EXPORT_DIR, fileName).
exports.post("/exports", requireUser, async (req, res) => {
  const fileName = String(req.body.fileName || "export.csv");
  const row = await db.exports.insert({ ownerId: req.user.id, fileName, createdAt: new Date() });
  await queueExport(row.id);
  res.status(202).json({ id: row.id });
});
JS

git add .
git commit -q -m "feat: user-named CSV exports"

git checkout -q -b feat/purge-old-exports
cat >src/jobs/purge-exports.js <<'JS'
import fs from "node:fs/promises";
import path from "node:path";
import { db } from "../db.js";

const EXPORT_DIR = process.env.EXPORT_DIR || "/srv/app/exports";
const MAX_AGE_MS = 7 * 24 * 60 * 60 * 1000;
const SAFE_NAME = /^[\w.\/-]+\.csv$/;

export async function purgeExports(now = Date.now()) {
  const expired = await db.exports.olderThan(new Date(now - MAX_AGE_MS));
  for (const row of expired) {
    if (!SAFE_NAME.test(row.fileName)) {
      continue;
    }
    await fs.rm(path.join(EXPORT_DIR, row.fileName), { force: true });
    await db.exports.delete(row.id);
  }
}
JS
git add .
git commit -q -m "feat: purge exports older than a week

Runs nightly. Names that are not plain CSV file names are skipped."

git diff main...HEAD >review-input/change.diff
