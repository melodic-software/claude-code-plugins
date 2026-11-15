#!/usr/bin/env bash
# The repository sets reproduce_findings: require on main, and the run is passed --unattended, so
# no proposed check may run. The branch plants two defects: isWeekend misses Sunday (getDay() is 0,
# not 7) and the CSV export writes raw customer emails. Both must stay listed in ## Findings, each
# one at or above the floor gets a "not reproduced" ## Dismissed line, and the report opens with
# the nothing-could-be-checked line.
set -euo pipefail

git init -q -b main
git config user.name eval
git config user.email eval@example.invalid
mkdir -p src test docs/conventions

cat >src/calendar.js <<'JS'
export function isWeekend(date) {
  const day = date.getDay();
  return day === 0 || day === 6;
}
JS

cat >src/shipping.js <<'JS'
import { isWeekend } from "./calendar.js";

// Orders placed on a weekend ship on the next working day.
export function shipsSameDay(placedAt) {
  return !isWeekend(placedAt);
}
JS

cat >test/calendar.test.js <<'JS'
import { test } from "node:test";
import assert from "node:assert/strict";
import { isWeekend } from "../src/calendar.js";

test("Saturday is a weekend day", () => {
  assert.equal(isWeekend(new Date(2026, 10, 14)), true);
});
JS

cat >package.json <<'JSON'
{ "name": "orders-service", "type": "module", "private": true, "scripts": { "test": "node --test" } }
JSON

cat >docs/conventions/review.yaml <<'YAML'
reproduce_findings: require
YAML

git add .
git commit -q -m "chore: initial import"
git remote add origin "$PWD"
git fetch -q origin
git remote set-head origin main >/dev/null

git checkout -q -b orders-export
cat >src/export-orders.js <<'JS'
export function exportOrdersCsv(orders) {
  const lines = ["id,email,total"];
  for (const order of orders) {
    lines.push(`${order.id},${order.customer.email},${order.total.toFixed(2)}`);
  }
  return lines.join("\n");
}
JS

cat >src/calendar.js <<'JS'
export function isWeekend(date) {
  return [6, 7].includes(date.getDay());
}
JS

git add .
git commit -q -m "feat: add an orders CSV export and shorten isWeekend"
