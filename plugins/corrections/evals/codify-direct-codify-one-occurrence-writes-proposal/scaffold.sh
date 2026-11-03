#!/usr/bin/env bash
set -euo pipefail
here="$(dirname "${BASH_SOURCE[0]}")"
bash "$here/../fixtures/repo.sh"
mkdir -p src/handlers
printf 'export const findUser = (db: { query: (sql: string, args?: unknown[]) => unknown }, name: string) =>\n  db.query("SELECT * FROM users WHERE name = '"'"'" + name + "'"'"'");\n' >src/handlers/users.ts
git add . && git commit -q -m "feat: add the user lookup handler"
printf 'export const findUser = (db: { query: (sql: string, args?: unknown[]) => unknown }, name: string) =>\n  db.query("SELECT * FROM users WHERE name = $1", [name]);\n' >src/handlers/users.ts
git add . && git commit -q -m "fix: the user lookup handler built its SQL by string concatenation"
