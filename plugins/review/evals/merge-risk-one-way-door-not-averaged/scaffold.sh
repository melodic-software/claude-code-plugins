#!/usr/bin/env bash
# main has a deploy script that migrates and restarts. The branch adds a purge step that
# deletes customer rows with no order in three years on every deploy, with a test, logged
# failures, screenshots in the body and a closing issue that asks for it. Deleted rows do
# not come back when the merge commit is reverted, so reversibility meets the HIGH floor
# however strong the other rows are.
set -euo pipefail

git init -q -b main
git config user.name eval
git config user.email eval@example.invalid
mkdir -p scripts test

cat >scripts/deploy.sh <<'SH'
#!/usr/bin/env bash
set -euo pipefail
node scripts/migrate.js
systemctl restart storefront
SH

cat >package.json <<'JSON'
{ "name": "storefront", "type": "module", "private": true, "scripts": { "test": "node --test" } }
JSON

git add .
git commit -q -m "chore: deploy script"
BASE=$(git rev-parse HEAD)

git checkout -q -b feat/90-purge-stale-customers
cat >scripts/deploy.sh <<'SH'
#!/usr/bin/env bash
set -euo pipefail
node scripts/migrate.js
node scripts/purge-stale-customers.js
systemctl restart storefront
SH

cat >scripts/purge-stale-customers.js <<'JS'
import { db } from "../src/db.js";

export const PURGE_SQL =
  "DELETE FROM customers WHERE last_order_at < now() - interval '3 years'";

export async function purgeStaleCustomers(client = db) {
  const result = await client.query(PURGE_SQL);
  console.log(`purged ${result.rowCount} stale customers`);
  return result.rowCount;
}

if (import.meta.url === `file://${process.argv[1]}`) {
  purgeStaleCustomers().catch((err) => {
    console.error("customer purge failed", err);
    process.exit(1);
  });
}
JS

cat >test/purge.test.js <<'JS'
import { test } from "node:test";
import assert from "node:assert/strict";
import { purgeStaleCustomers, PURGE_SQL } from "../scripts/purge-stale-customers.js";

test("purge deletes customers with no order in three years", async () => {
  const calls = [];
  const client = { query: async (sql) => (calls.push(sql), { rowCount: 2 }) };
  assert.equal(await purgeStaleCustomers(client), 2);
  assert.deepEqual(calls, [PURGE_SQL]);
});

test("purge rejects when the query fails", async () => {
  const client = { query: async () => { throw new Error("connection lost"); } };
  await assert.rejects(purgeStaleCustomers(client), /connection lost/);
});
JS

git add .
git commit -q -m "feat(deploy): purge stale customers on deploy

Closes #90"
HEAD_OID=$(git rev-parse HEAD)

mkdir -p .claude-lane/pr
git diff main...HEAD >.claude-lane/pr/pr.diff
cp "$(dirname "${BASH_SOURCE[0]}")/fixtures/issue.md" .claude-lane/pr/issue.md

cat >.claude-lane/pr/facts.json <<JSON
{
  "number": 91,
  "url": "https://github.com/acme/storefront/pull/91",
  "state": "OPEN",
  "isDraft": false,
  "title": "feat(deploy): purge stale customers on deploy",
  "body": "Closes #90\n\n## Summary\n\nEach deploy now deletes customers with no order in three years, as the retention policy requires.\n\n## Verification\n\n- Unit tests cover the delete and the failure path.\n- Ran the deploy against staging: before and after screenshots of the customer count are attached.\n- A failed purge logs the error and exits 1, which fails the deploy.",
  "baseRefName": "main",
  "headRefName": "feat/90-purge-stale-customers",
  "baseRefOid": "$BASE",
  "headRefOid": "$HEAD_OID",
  "files": [
    { "path": "scripts/deploy.sh", "additions": 1, "deletions": 0 },
    { "path": "scripts/purge-stale-customers.js", "additions": 17, "deletions": 0 },
    { "path": "test/purge.test.js", "additions": 15, "deletions": 0 }
  ],
  "labels": [],
  "visibility": "PUBLIC"
}
JSON
