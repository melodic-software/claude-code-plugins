#!/usr/bin/env bash
# Decoy fixture return-promise, with docs/conventions/review.yaml committed on main so the run
# reads fanout_diversity from the repository layer and the reviewed diff never edits it.
# The branch drops the await in loadProfile's return of findUser. The change is correct:
# loadProfile stays async with no try block, so its promise settles the same way, and the route
# awaits it inside its own try block.
set -euo pipefail

git init -q -b main
git config user.name eval
git config user.email eval@example.invalid
mkdir -p src/routes docs/conventions

cat >docs/conventions/review.yaml <<'YAML'
fanout_diversity: model
YAML

cat >src/db.js <<'JS'
import pg from "pg";

export const pool = new pg.Pool();
JS

cat >src/users.js <<'JS'
import { pool } from "./db.js";

export async function findUser(id) {
  const { rows } = await pool.query("SELECT id, name FROM users WHERE id = $1", [id]);
  return rows[0] ?? null;
}

export async function loadProfile(id) {
  return await findUser(id);
}
JS

cat >src/routes/profile.js <<'JS'
import { Router } from "express";
import { loadProfile } from "../users.js";

export const profile = Router();

profile.get("/users/:id", async (req, res, next) => {
  try {
    const user = await loadProfile(req.params.id);
    if (!user) {
      res.status(404).end();
      return;
    }
    res.json(user);
  } catch (err) {
    next(err);
  }
});
JS

cat >package.json <<'JSON'
{
  "name": "profile-api",
  "type": "module",
  "private": true,
  "dependencies": { "express": "^4.21.0", "pg": "^8.13.0" }
}
JSON

git add .
git commit -q -m "feat: profile lookup route"
git remote add origin "$PWD"
git fetch -q origin
git remote set-head origin main >/dev/null

git checkout -q -b refactor/return-await
cat >src/users.js <<'JS'
import { pool } from "./db.js";

export async function findUser(id) {
  const { rows } = await pool.query("SELECT id, name FROM users WHERE id = $1", [id]);
  return rows[0] ?? null;
}

export async function loadProfile(id) {
  return findUser(id);
}
JS
git commit -q -am "refactor: drop the redundant await in loadProfile

An async function's return already adopts the promise it returns, and
loadProfile has no try block for the await to matter in."
