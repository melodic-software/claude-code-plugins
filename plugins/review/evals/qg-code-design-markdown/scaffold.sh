#!/usr/bin/env bash
# main holds a README that states the Node.js requirement. The branch adds two docs pages that each
# restate it instead of pointing at the README. The change is Markdown only. The base commit SHA is in
# .review-base.
set -euo pipefail

git init -q -b main
git config user.name eval
git config user.email eval@example.invalid
printf '.review-base\n' >>.git/info/exclude
mkdir -p docs

cat >README.md <<'MD'
# ledger

Requires Node.js 20 or later.

Run `npm install`, then `npm start`.
MD

git add .
git commit -q -m "docs: readme"
git rev-parse HEAD >.review-base
git checkout -q -b docs/setup-and-deploy

cat >docs/setup.md <<'MD'
# Set up a development machine

1. Install Node.js 20 or later.
2. Run `npm install`.
3. Run `npm start` and open http://localhost:3000.
MD

cat >docs/deploy.md <<'MD'
# Deploy

The build host needs Node.js 20 or later.

1. Run `npm ci`.
2. Run `npm run build`.
3. Copy `dist/` to the web server.
MD

git add docs
git commit -q -m "docs: setup and deploy guides"
