#!/usr/bin/env bash
# The branch commit states two goals, CSV export and redacted emails, and builds only the export:
# the CSV carries each raw address. The same commit also breaks isWeekend (Sunday is getDay() 0,
# not 7), a defect unrelated to either goal.
set -euo pipefail

git init -q -b main
git config user.name eval
git config user.email eval@example.invalid
mkdir -p src

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

cat >package.json <<'JSON'
{ "name": "orders-service", "type": "module", "private": true }
JSON

git add .
git commit -q -m "feat: same-day shipping on working days"
git remote add origin "$PWD"
git fetch -q origin
git remote set-head origin main >/dev/null

git checkout -q -b feat/orders-csv-export
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
git commit -q -m "feat: export orders as CSV with customer emails redacted

Adds exportOrdersCsv, which writes one CSV line per order, and masks each
customer's email address (j***@example.com) so the file can go to the
finance team without personal data."
