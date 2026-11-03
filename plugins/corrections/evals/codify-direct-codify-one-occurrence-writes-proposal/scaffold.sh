#!/usr/bin/env bash
set -euo pipefail
here="$(dirname "${BASH_SOURCE[0]}")"
bash "$here/../fixtures/repo.sh"
mkdir -p src/handlers
cat >src/handlers/users.ts <<'EOF'
export const findUser = (db: { query: (sql: string, args?: unknown[]) => unknown }, name: string) =>
  db.query("SELECT * FROM users WHERE name = '" + name + "'");
EOF
git add . && git commit -q -m "feat: add the user lookup handler"
cat >src/handlers/users.ts <<'EOF'
export const findUser = (db: { query: (sql: string, args?: unknown[]) => unknown }, name: string) =>
  db.query("SELECT * FROM users WHERE name = $1", [name]);
EOF
git add . && git commit -q -m "fix: the user lookup handler built its SQL by string concatenation"
