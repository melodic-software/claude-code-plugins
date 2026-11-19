#!/usr/bin/env bash
set -euo pipefail

git init -q -b main .
git config user.email eval@example.invalid
git config user.name eval

mkdir -p src/routes
cat >package.json <<'EOF'
{
  "name": "orders-api",
  "private": true,
  "type": "module",
  "scripts": {
    "build": "tsc -p .",
    "test": "node --test"
  },
  "dependencies": {
    "express": "^5.1.0"
  },
  "devDependencies": {
    "typescript": "^5.6.0"
  }
}
EOF
cat >src/routes/orders.ts <<'EOF'
import { Router } from "express";
import { saveOrder } from "../store.js";

export const orders = Router();

orders.post("/orders", async (req, res) => {
  const order = await saveOrder(req.body);
  res.status(201).json(order);
});
EOF
cat >src/store.ts <<'EOF'
const rows: unknown[] = [];

export const saveOrder = async (order: unknown) => {
  rows.push(order);
  return order;
};
EOF
cat >CLAUDE.md <<'EOF'
# orders-api

Run `npm run build` and `npm test` before committing.
EOF

course=courses/teachable/robust-http-apis-hale
mkdir -p "$course/modules/01-request-handling" "$course/modules/02-testing-the-edges" "$course/analysis"
cat >"$course/course.json" <<'JSON'
{
  "title": "Robust HTTP APIs in TypeScript",
  "slug": "robust-http-apis-hale",
  "platform": "teachable",
  "url": "https://courses.example.invalid/p/robust-http-apis",
  "instructor": "Rowan Hale",
  "totalLessons": 6,
  "status": "analyzed",
  "modules": [
    { "position": 1, "title": "Request handling", "slug": "01-request-handling", "lessons": [] },
    { "position": 2, "title": "Testing the edges", "slug": "02-testing-the-edges", "lessons": [] }
  ],
  "phases": {
    "extract": { "completedAt": "2026-10-02T09:00:00Z", "lessonsExtracted": 6 },
    "extractFrames": { "completedAt": "2026-10-02T10:00:00Z", "framesExtracted": 48 },
    "processFrames": { "completedAt": "2026-10-02T10:20:00Z", "manifests": 6, "kept": 35 },
    "analyzeCodeRepo": { "completedAt": "2026-10-02T10:40:00Z", "sections": 2 },
    "validate": { "completedAt": "2026-10-02T10:45:00Z", "passed": 8, "warnings": 0, "failed": 0 },
    "synthesize": { "completedAt": "2026-10-03T08:00:00Z" },
    "analyze": { "completedAt": "2026-10-03T09:00:00Z" }
  }
}
JSON
cat >"$course/modules/01-request-handling/module-summary.md" <<'EOF'
# Module: Request handling

**Lessons:** 3 | **Duration:** ~40 min | `[full-context]`

## Key concepts

- **Trust boundary**: every byte from the network is untrusted until a schema accepts it. (Lesson: "Where untrusted data enters")
- **Parse, don't validate**: turn the raw body into a typed value once, at the edge. (Lesson: "Schemas at the edge")

## Code patterns demonstrated

- A `zod` schema per route, applied in a small middleware before the handler runs; the handler receives only the parsed value.

## Best practices advocated

- Validate request bodies at the boundary: every route that reads a body parses it with a schema before any handler or store code sees it, and rejects unknown fields with a 400.

## Anti-patterns warned against

- Passing `req.body` straight to persistence code, so a malformed or oversized payload reaches the database.

## Tools and frameworks mentioned

- zod 3, Express 5
EOF
cat >"$course/modules/02-testing-the-edges/module-summary.md" <<'EOF'
# Module: Testing the edges

**Lessons:** 3 | **Duration:** ~35 min | `[full-context]`

## Key concepts

- **Contract tests per route**: one test per route that posts a malformed body and expects a 400. (Lesson: "Testing bad input")

## Code patterns demonstrated

- `node:test` with `supertest` against the app instance, no network.

## Best practices advocated

- Keep a fixture of known-bad payloads and run every route against it.

## Anti-patterns warned against

- Testing only the happy path, so a missing schema goes unnoticed.

## Tools and frameworks mentioned

- node:test, supertest
EOF
cat >"$course/analysis/course-summary.md" <<'EOF'
# Course summary: Robust HTTP APIs in TypeScript

Instructor: Rowan Hale. Two modules, six lessons.

## Cross-cutting themes

- The request body is the main trust boundary. Module 1 teaches one rule: validate request bodies
  at the boundary, with a schema per route, before any handler or store code reads them.
- Module 2 backs the rule with tests: each route gets a malformed-body test that expects a 400.

## Instructor's approach

Small, explicit middleware over framework magic; the schema is the route's contract.

## Tensions

None between modules.
EOF

git add .
git commit -q -m "feat(orders): create-order route"
