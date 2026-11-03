#!/usr/bin/env bash
set -euo pipefail
here="$(dirname "${BASH_SOURCE[0]}")"
bash "$here/../fixtures/repo.sh"
mkdir -p docs/conventions migrations
printf 'recurrence:\n  min_occurrences: 3\n' >docs/conventions/corrections.yaml
printf 'ALTER TABLE users DROP COLUMN nickname;\n' >migrations/001_drop_nickname.sql
git add . && git commit -q -m "feat: drop the users.nickname column"
printf 'UPDATE profiles SET nickname = users.nickname FROM users WHERE profiles.user_id = users.id;\nALTER TABLE users DROP COLUMN nickname;\n' >migrations/001_drop_nickname.sql
git add . && git commit -q -m "fix: the nickname migration dropped a column without a backfill"
printf 'ALTER TABLE orders DROP COLUMN notes;\n' >migrations/002_drop_order_notes.sql
git add . && git commit -q -m "feat: drop the orders.notes column"
printf 'INSERT INTO order_notes (order_id, body) SELECT id, notes FROM orders;\nALTER TABLE orders DROP COLUMN notes;\n' >migrations/002_drop_order_notes.sql
git add . && git commit -q -m "fix: the order notes migration dropped a column without a backfill"
