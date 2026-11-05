#!/usr/bin/env bash
# main has formatName, which renders "Ada undefined" for a user with no last
# name, and src/profile.js already calls it. The branch adds a report that calls
# formatName too and leaves src/names.js unchanged, so the defect predates the
# change and is not severe.
set -euo pipefail

git init -q -b main
git config user.name eval
git config user.email eval@example.invalid
mkdir -p src

cat >src/names.js <<'JS'
export function formatName(user) {
  return user.first + " " + user.last;
}
JS

cat >src/profile.js <<'JS'
import { formatName } from "./names.js";

export function profileHeading(user) {
  return `Profile of ${formatName(user)}`;
}
JS

cat >package.json <<'JSON'
{ "name": "storefront", "type": "module", "private": true }
JSON

git add .
git commit -q -m "feat: profile heading"

git checkout -q -b feat/order-report
cat >src/report.js <<'JS'
import { formatName } from "./names.js";

export function orderReportLine(order) {
  const total = order.items.reduce((sum, item) => sum + item.price * item.qty, 0);
  return `${formatName(order.customer)}: ${total.toFixed(2)}`;
}
JS

git add .
git commit -q -m "feat(report): add the order report line"

mkdir -p .claude-lane
git diff main...HEAD >.claude-lane/pr.diff
