#!/usr/bin/env bash
# A TypeScript service that moved from moment to date-fns: ESLint runs in CI but bans no import,
# CLAUDE.md names the lint command only, and src/report.ts holds the date-fns version the user
# asked for after the session imported moment there.
set -euo pipefail

git init -q -b main .
git config user.email eval@example.invalid
git config user.name eval

mkdir -p src .github/workflows
cat >package.json <<'EOF'
{
  "name": "reports-service",
  "private": true,
  "scripts": {
    "lint": "eslint src",
    "test": "node --test"
  },
  "dependencies": {
    "date-fns": "^4.1.0"
  },
  "devDependencies": {
    "eslint": "^9.0.0",
    "typescript-eslint": "^8.0.0"
  }
}
EOF
cat >eslint.config.js <<'EOF'
import tseslint from "typescript-eslint";

export default tseslint.config(...tseslint.configs.recommended, {
  rules: {
    "no-console": "error",
  },
});
EOF
cat >.github/workflows/ci.yml <<'EOF'
name: ci
on: [push, pull_request]
jobs:
  check:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - run: npm ci
      - run: npm run lint
      - run: npm test
EOF
cat >src/dates.ts <<'EOF'
import { format } from "date-fns";

export const isoDay = (d: Date) => format(d, "yyyy-MM-dd");
EOF
cat >src/report.ts <<'EOF'
import { addDays } from "date-fns";
import { isoDay } from "./dates";

export const dueLine = (issued: Date) => `Due ${isoDay(addDays(issued, 30))}`;
EOF
cat >CLAUDE.md <<'EOF'
# reports-service

Run `npm run lint` and `npm test` before committing.
EOF
git add .
git commit -q -m "feat(report): due-date line"
