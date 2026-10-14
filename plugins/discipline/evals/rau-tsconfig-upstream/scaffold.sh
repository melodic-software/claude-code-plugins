#!/usr/bin/env bash
# Seed a TypeScript 5.4 project whose tsconfig holds a deprecated flag, an ADR-backed divergence
# and an unexplained one.
set -euo pipefail

mkdir -p docs/adr src/app src/legacy
cat >package.json <<'JSON'
{
  "name": "web-app",
  "private": true,
  "devDependencies": { "typescript": "5.4.5" }
}
JSON
cat >tsconfig.json <<'JSON'
{
  "compilerOptions": {
    "target": "ES2022",
    "module": "ESNext",
    "moduleResolution": "Bundler",
    "strict": false,
    "importsNotUsedAsValues": "remove",
    "useDefineForClassFields": false,
    "outDir": "dist"
  },
  "include": ["src"]
}
JSON
cat >docs/adr/0003-strict-off-until-legacy-migrates.md <<'MD'
# ADR 0003: Keep `strict` off until src/legacy/ is migrated

Status: accepted (2025-02-10)

Context: src/legacy/ has about 400 implicit-any errors under `strict`.

Decision: keep `"strict": false` in tsconfig.json until the src/legacy/ migration (issue #12) lands.
MD
cat >src/legacy/old.ts <<'TS'
export function total(items) {
  return items.reduce((sum, item) => sum + item.price, 0);
}
TS
cat >src/app/main.ts <<'TS'
import { total } from "../legacy/old";
console.log(total([{ price: 2 }]));
TS
