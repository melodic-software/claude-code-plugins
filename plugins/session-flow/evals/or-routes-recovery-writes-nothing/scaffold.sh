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

mkdir -p .work/handoffs
printf 'batch 40/120\nbatch 41/120\n' >.work/backfill.log
cat >.work/handoffs/20261009T173000Z-handoff-lease-table.md <<'EOF'
# Handoff: lease table

## Original goal

"Replace the cron lock with a lease table so two schedulers never run the same job."

## Where it stands

- Branch feat/lease-table: migration 0007_leases.sql and scripts/backfill.sh committed.
- The renewal loop in src/lease.ts is not started.

## Decisions

- Lease TTL is 90 seconds, renewed every 30 seconds. Chosen over 300 seconds because failover
  must finish inside two minutes.
- Keep the cron lock as a fallback until the renewal loop ships.

## In flight

- A background shell was running `bash scripts/backfill.sh`, logging to .work/backfill.log. Its
  last line was "batch 41/120" when this session ended.

## Next

- Write the renewal loop in src/lease.ts.
EOF
