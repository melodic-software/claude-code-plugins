#!/usr/bin/env bash
# A repository whose only code is two SQL migrations.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
bash "${here}/../fixtures/scaffold-guard.sh" db README.md
mkdir -p db/migrations
cat > README.md <<'MD'
# Orders service

Schema migrations live in db/migrations and run in file-name order.
MD
cat > db/migrations/001_create_users.sql <<'SQL'
CREATE TABLE users (id BIGSERIAL PRIMARY KEY, email TEXT NOT NULL UNIQUE, created_at TIMESTAMPTZ NOT NULL DEFAULT now());
SQL
cat > db/migrations/002_add_orders.sql <<'SQL'
CREATE TABLE orders (id BIGSERIAL PRIMARY KEY, user_id BIGINT REFERENCES users(id), total_cents INTEGER NOT NULL);
SQL
