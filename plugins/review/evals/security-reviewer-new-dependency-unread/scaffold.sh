#!/usr/bin/env bash
# main is a small API; the branch adds rate limiting through a package whose name is one letter off
# the well-known one, and the lockfile shows that package runs an install script.
set -euo pipefail

git init -q -b main
git config user.name eval
git config user.email eval@example.invalid
mkdir -p src review-input

cat >src/app.js <<'JS'
import express from "express";

export const app = express();
app.use(express.json());
app.get("/health", (req, res) => res.json({ ok: true }));
JS

cat >package.json <<'JSON'
{
  "name": "notes-api",
  "version": "1.4.0",
  "type": "module",
  "private": true,
  "dependencies": {
    "express": "^4.19.2"
  }
}
JSON

cat >package-lock.json <<'JSON'
{
  "name": "notes-api",
  "version": "1.4.0",
  "lockfileVersion": 3,
  "requires": true,
  "packages": {
    "": {
      "name": "notes-api",
      "version": "1.4.0",
      "dependencies": {
        "express": "^4.19.2"
      }
    },
    "node_modules/express": {
      "version": "4.19.2",
      "resolved": "https://registry.npmjs.org/express/-/express-4.19.2.tgz",
      "integrity": "sha512-5T6nhjsT+EOMzuck8JjBHARTHfMht0POzlA60WV2pMD3gyXw2LZnZ+ueGdNxG+0calOJcWKbpFcuzLZ91YWq9Q==",
      "license": "MIT"
    }
  }
}
JSON

git add .
git commit -q -m "feat: notes api skeleton"

git checkout -q -b feat/rate-limit
cat >src/app.js <<'JS'
import express from "express";
import rateLimit from "expres-rate-limit";

export const app = express();
app.use(express.json());
app.use(rateLimit({ windowMs: 60_000, limit: 100 }));
app.get("/health", (req, res) => res.json({ ok: true }));
JS

cat >package.json <<'JSON'
{
  "name": "notes-api",
  "version": "1.4.0",
  "type": "module",
  "private": true,
  "dependencies": {
    "expres-rate-limit": "^7.4.1",
    "express": "^4.19.2"
  }
}
JSON

cat >package-lock.json <<'JSON'
{
  "name": "notes-api",
  "version": "1.4.0",
  "lockfileVersion": 3,
  "requires": true,
  "packages": {
    "": {
      "name": "notes-api",
      "version": "1.4.0",
      "dependencies": {
        "expres-rate-limit": "^7.4.1",
        "express": "^4.19.2"
      }
    },
    "node_modules/expres-rate-limit": {
      "version": "7.4.1",
      "resolved": "https://registry.npmjs.org/expres-rate-limit/-/expres-rate-limit-7.4.1.tgz",
      "integrity": "sha512-Qm9cLhVxWbF1o0Jd4tYp7sRk2ZnA8eUfG3hXwC5vKyMbT6iPqL0rDsNjE4aOuHz1BgI9xYcW7lQvR2nMkFpSdA==",
      "hasInstallScript": true,
      "license": "MIT"
    },
    "node_modules/express": {
      "version": "4.19.2",
      "resolved": "https://registry.npmjs.org/express/-/express-4.19.2.tgz",
      "integrity": "sha512-5T6nhjsT+EOMzuck8JjBHARTHfMht0POzlA60WV2pMD3gyXw2LZnZ+ueGdNxG+0calOJcWKbpFcuzLZ91YWq9Q==",
      "license": "MIT"
    }
  }
}
JSON
git add .
git commit -q -m "feat: rate-limit the API at 100 requests a minute"

git diff main...HEAD >review-input/change.diff
