#!/usr/bin/env bash
# Seeds a repository whose CLAUDE.md has fixable problems (a missing path, a
# command the manifest lacks, restated conventions) and no audit on record.
set -euo pipefail

git init -q -b main
git config user.name dev
git config user.email dev@example.invalid

mkdir -p src
cat >CLAUDE.md <<'MD'
# Parcel tracker

Tracks shipments for the warehouse team.

## Commands

- Build: `npm run compile`
- Test: `npm test`

## Style

- Use camelCase for variables.
- Prefer const over let.
- Write clear commit messages.

## Where things are

- Carrier adapters live in `src/carriers/`.
- The label printer driver is in `lib/printer/driver.ts`.
MD

cat >package.json <<'JSON'
{
  "name": "parcel-tracker",
  "private": true,
  "scripts": {
    "build": "tsc -p .",
    "test": "vitest run"
  }
}
JSON

mkdir -p src/carriers
printf 'export const carriers = [];\n' >src/carriers/index.ts

git add -A
git commit -q -m "chore: initial commit"
