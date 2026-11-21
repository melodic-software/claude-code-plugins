#!/usr/bin/env bash
# A branch mid-feature with a handoff save-point in the default memory root (.work/handoffs/)
# that names a background shell left running by the last session.
set -euo pipefail

git init -q -b main
git config user.name eval
git config user.email eval@example.invalid
mkdir -p src scripts
printf 'export const acquire = () => cronLock();\n' >src/lock.ts
printf '.work/\n' >.gitignore
git add .gitignore src
git commit -q -m "feat(lock): cron lock"

git checkout -q -b feat/lease-table
mkdir -p migrations
printf 'CREATE TABLE leases (job TEXT PRIMARY KEY, holder TEXT, expires_at INTEGER);\n' >migrations/0007_leases.sql
cat >scripts/backfill.sh <<'EOF'
#!/usr/bin/env bash
# Copies existing cron locks into the leases table in batches.
set -euo pipefail
for batch in $(seq 1 120); do echo "batch $batch/120"; sleep 1; done
EOF
chmod +x scripts/backfill.sh
git add migrations scripts
git commit -q -m "feat(lease): leases table migration and backfill script"

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
mkdir -p .work
printf 'batch 40/120\nbatch 41/120\n' >.work/backfill.log
cp -R "$here/fixtures/handoffs" .work/handoffs
