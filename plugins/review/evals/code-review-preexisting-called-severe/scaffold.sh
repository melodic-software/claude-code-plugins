#!/usr/bin/env bash
# main has purgeOlderThan, whose cutoff subtracts days * 86400 (seconds) from
# Date.now() (milliseconds), so it deletes every record older than a few
# minutes; the admin CLI already calls it. The branch adds a nightly job that
# calls it and leaves src/cleanup.js unchanged: a pre-existing data-loss defect
# with a one-line fix.
set -euo pipefail

git init -q -b main
git config user.name eval
git config user.email eval@example.invalid
mkdir -p src

cat >src/cleanup.js <<'JS'
import { store } from "./store.js";

export function purgeOlderThan(days) {
  const cutoff = Date.now() - days * 86400;
  return store.deleteWhere((record) => record.createdAt < cutoff);
}
JS

cat >src/store.js <<'JS'
const records = [];

export const store = {
  insert(record) {
    records.push(record);
  },
  deleteWhere(predicate) {
    let removed = 0;
    for (let i = records.length - 1; i >= 0; i--) {
      if (predicate(records[i])) {
        records.splice(i, 1);
        removed++;
      }
    }
    return removed;
  },
};
JS

cat >src/admin.js <<'JS'
import { purgeOlderThan } from "./cleanup.js";

export function adminPurge(args) {
  return purgeOlderThan(Number(args.days));
}
JS

cat >package.json <<'JSON'
{ "name": "storefront", "type": "module", "private": true }
JSON

git add .
git commit -q -m "feat: admin purge command"

git checkout -q -b feat/nightly-purge
cat >src/nightly.js <<'JS'
import { purgeOlderThan } from "./cleanup.js";

export function runNightly(log) {
  const removed = purgeOlderThan(30);
  log(`nightly purge removed ${removed} records older than 30 days`);
}
JS

git add .
git commit -q -m "feat(nightly): purge records older than 30 days every night"

mkdir -p .claude-lane
git diff main...HEAD >.claude-lane/pr.diff
