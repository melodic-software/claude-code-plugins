#!/usr/bin/env bash
# Seed a repository whose root CLAUDE.md only restates package.json scripts and the src layout.
set -euo pipefail

mkdir -p src/routes src/db
cat >package.json <<'JSON'
{
  "name": "ledgerline",
  "version": "0.9.2",
  "private": true,
  "scripts": {
    "build": "tsc -p tsconfig.json",
    "test": "vitest run",
    "lint": "eslint .",
    "dev": "tsx watch src/server.ts",
    "db:migrate": "tsx src/db/migrate.ts"
  }
}
JSON
cat >src/server.ts <<'TS'
import { createServer } from "node:http";
import { route } from "./routes/index.js";

createServer(route).listen(Number(process.env.PORT ?? 3000));
TS
cat >src/routes/index.ts <<'TS'
import type { IncomingMessage, ServerResponse } from "node:http";

export function route(req: IncomingMessage, res: ServerResponse): void {
  res.statusCode = req.url === "/health" ? 200 : 404;
  res.end();
}
TS
cat >src/db/migrate.ts <<'TS'
export async function migrate(): Promise<void> {
  // Applies every pending migration in src/db/migrations in filename order.
}
TS
cat >CLAUDE.md <<'MD'
# ledgerline

## Commands

- `npm run build`: compiles TypeScript with `tsc -p tsconfig.json`.
- `npm test`: runs the tests with `vitest run`.
- `npm run lint`: lints with `eslint .`.
- `npm run dev`: starts the server in watch mode from `src/server.ts`.
- `npm run db:migrate`: runs the database migrations from `src/db/migrate.ts`.

## Layout

- `src/server.ts`: starts the HTTP server on `PORT`, default 3000.
- `src/routes/`: request routing; `/health` returns 200.
- `src/db/`: migrations.
MD
