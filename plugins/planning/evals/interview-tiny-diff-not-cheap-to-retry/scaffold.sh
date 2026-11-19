#!/usr/bin/env bash
set -euo pipefail

mkdir -p src/jobs
cat >src/jobs/purge-audit-log.ts <<'TS'
// Runs every hour against the production database.
// Deleted rows cannot be restored: audit_log has no backup, no soft delete and no replica.
export const RETENTION_DAYS = 90;

export interface Db {
  query(sql: string, params: unknown[]): Promise<void>;
}

export async function purgeAuditLog(db: Db): Promise<void> {
  await db.query(
    "DELETE FROM audit_log WHERE created_at < now() - make_interval(days => $1)",
    [RETENTION_DAYS],
  );
}
TS
