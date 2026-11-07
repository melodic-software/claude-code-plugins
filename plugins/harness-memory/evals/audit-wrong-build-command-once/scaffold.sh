#!/usr/bin/env bash
# Seeds a repository whose CLAUDE.md names its tools without invocations and
# gives a build command package.json does not define.
set -euo pipefail

git init -q -b main
git config user.name dev
git config user.email dev@example.invalid

mkdir -p src
cat >CLAUDE.md <<'MD'
# Trailhead

Route planner for hiking clubs.

## Tooling

We use pnpm and vitest.

Build with `pnpm run compile` before opening a pull request.

## Conventions

- Distances are stored in meters and shown in the club's chosen unit.
- Route files under `src/routes/` are GPX; never hand-edit them.
MD

cat >package.json <<'JSON'
{
  "name": "trailhead",
  "private": true,
  "packageManager": "pnpm@9.12.0",
  "scripts": {
    "build": "tsc -p .",
    "test": "vitest run",
    "lint": "eslint ."
  }
}
JSON

mkdir -p src/routes
printf 'export const meters = (n: number) => n;\n' >src/units.ts

git add -A
git commit -q -m "chore: initial commit"
