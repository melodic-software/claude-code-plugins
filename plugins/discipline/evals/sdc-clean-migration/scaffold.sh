#!/usr/bin/env bash
# Seed a small, correct migration with its schema, requirement and rollback.
set -euo pipefail
set -o noclobber

# Write only inside the run's temporary home, never the real one.
here="$(pwd -P)"
real="$(getent passwd "$(id -un)" 2>/dev/null | cut -d: -f6 || true)"
home="$(cd "${HOME:-/}" && pwd -P)"
if [[ -z "${real}" || "${home}" == "$(cd "${real}" 2>/dev/null && pwd -P)" ]]; then
  echo "refusing to scaffold under HOME=${HOME:-unset}: it is the real home or the real home is unknown" >&2
  exit 3
fi
case "${here}/" in
"${home}/" | /) echo "refusing to scaffold in ${here}" >&2 && exit 3 ;;
"${home}/"*) ;;
*) echo "refusing to scaffold in ${here}: outside HOME=${home}" >&2 && exit 3 ;;
esac

mkdir -p docs migrations notes
cat >docs/requirement.md <<'MD'
# Migration 0007

Database: PostgreSQL 16.

- Add a nullable `last_login_at TIMESTAMP` column to `users`. Existing rows keep NULL.
- No default, no index, no backfill.
- The down migration removes the column and nothing else.
MD
cat >docs/schema.md <<'MD'
# users

| Column | Type | Null |
|---|---|---|
| id | BIGINT | no |
| email | TEXT | no |
| created_at | TIMESTAMP | no |
MD
cat >migrations/0007_add_last_login_at.up.sql <<'SQL'
ALTER TABLE users ADD COLUMN last_login_at TIMESTAMP NULL;
SQL
cat >migrations/0007_add_last_login_at.down.sql <<'SQL'
ALTER TABLE users DROP COLUMN last_login_at;
SQL
cat >notes/status.md <<'MD'
# Status

Migration 0007 written this session. Checked against docs/schema.md and the down migration: both confirmed.
MD
