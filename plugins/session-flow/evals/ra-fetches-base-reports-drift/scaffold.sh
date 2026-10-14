#!/usr/bin/env bash
# A feature branch whose handoff claims main has not moved and feat/retry-backoff is not on main.
# Since then origin/main gained three commits (a retry-backoff merge among them), but the local
# origin/main tracking ref was never updated, so only a fetch of the base shows the drift.
set -euo pipefail

root="$PWD"
git init -q --bare -b main .remote/origin.git
git init -q -b main
git config user.name eval
git config user.email eval@example.invalid
printf '.work/\n' >.gitignore
mkdir -p src
printf 'export const acquire = () => cronLock();\n' >src/lock.ts
git add .gitignore src
git commit -q -m "feat(lock): cron lock"
printf '.remote/\n' >>.git/info/exclude
git remote add origin "$root/.remote/origin.git"
git push -q origin main
git remote set-head origin main

git checkout -q -b feat/lease-table
mkdir -p migrations
printf 'CREATE TABLE leases (job TEXT PRIMARY KEY, holder TEXT, expires_at INTEGER);\n' >migrations/0007_leases.sql
git add migrations
git commit -q -m "feat(lease): leases table migration"

git clone -q .remote/origin.git .remote/other
git -C .remote/other config user.name eval
git -C .remote/other config user.email eval@example.invalid
git -C .remote/other checkout -q -b feat/retry-backoff
printf 'export const backoff = (n) => 2 ** n * 100;\n' >.remote/other/src/backoff.ts
git -C .remote/other add src/backoff.ts
git -C .remote/other commit -q -m "feat(retry): exponential backoff helper"
git -C .remote/other checkout -q main
git -C .remote/other merge -q --no-ff -m "Merge branch 'feat/retry-backoff' (#12)" feat/retry-backoff
printf 'export const acquire = () => cronLock({ timeoutMs: 5000 });\n' >.remote/other/src/lock.ts
git -C .remote/other commit -q -am "fix(lock): bound the cron lock wait"
git -C .remote/other push -q origin main feat/retry-backoff
rm -rf .remote/other

mkdir -p .work/handoffs
cat >.work/handoffs/20261008T160000Z-handoff-lease-table.md <<'EOF'
# Handoff: lease table

## Original goal

"Replace the cron lock with a lease table so two schedulers never run the same job."

## Premises

- Base is main. feat/lease-table was up to date with main when this was written.
- feat/retry-backoff (PR #12) is open and not on main yet, so the renewal loop must not import
  its backoff helper until it merges.

## Next

- Write the renewal loop in src/lease.ts, with a fixed 1-second retry until PR #12 merges.
EOF
