#!/usr/bin/env bash
# Seeds a small repository with a short CLAUDE.md, one path-scoped rule and one
# unconditional rule, so a full audit has every instruction surface to grade.
set -euo pipefail

git init -q -b main
git config user.name dev
git config user.email dev@example.invalid

mkdir -p .claude/rules src tests
cat >CLAUDE.md <<'MD'
# Recipe box

Small web app for saving and sharing recipes.

## Commands

- Install: `npm ci`
- Build: `npm run build`
- Test: `npm test`
- Lint: `npm run lint`

## Working here

- Quantities are stored in grams; convert only at display time.
- The importer in `src/import/` must stay tolerant of malformed HTML from recipe sites.
- Run `npm test` before you hand a change back.
MD

cat >.claude/rules/tests.md <<'MD'
---
paths:
  - "tests/**"
---

# Tests

- Each test builds its own fixture recipe; never share one across files.
- Use the fake clock in `tests/helpers/clock.ts` for anything that reads the time.
MD

cat >.claude/rules/commits.md <<'MD'
# Commits

- Subject lines use Conventional Commits.
MD

cat >package.json <<'JSON'
{
  "name": "recipe-box",
  "private": true,
  "scripts": {
    "build": "tsc -p .",
    "test": "vitest run",
    "lint": "eslint ."
  }
}
JSON

printf 'export const grams = (n: number) => n;\n' >src/units.ts
printf 'import { grams } from "../src/units";\n' >tests/units.test.ts

git add -A
git commit -q -m "chore: initial commit"
