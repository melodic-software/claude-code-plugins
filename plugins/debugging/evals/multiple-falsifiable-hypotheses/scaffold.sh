#!/usr/bin/env bash
# A Node report exporter whose latest commit labels columns through config/columns.json, an
# uncommitted test that crashes on an unmapped column, an ADR making the footer optional, and a
# known-issues note on null dates: three suspects the repository itself can rank.
set -euo pipefail

git init -q -b main
git config user.name eval
git config user.email eval@example.invalid
mkdir -p src/exporter test docs/adr config

cat > package.json <<'JSON'
{
  "name": "ticket-reports",
  "version": "2.3.0",
  "private": true,
  "scripts": { "test": "node --test" }
}
JSON

cat > src/exporter/dates.js <<'JS'
function formatDate(value) {
  if (!value) return null;
  return new Date(value).toISOString().slice(0, 10);
}

module.exports = { formatDate };
JS

cat > src/exporter/report.js <<'JS'
const { formatDate } = require("./dates");

function exportReport(rows, options = {}) {
  const fields = Object.keys(rows[0] || {});
  const header = fields.map((field) => field.toUpperCase()).join(",");
  const body = rows.map((row) =>
    fields.map((field) => (field === "closedAt" ? formatDate(row[field]) : row[field])).join(","),
  );
  const footer = options.footer ? options.footer.text.trim() : "";
  return [header, ...body, footer].join("\n");
}

module.exports = { exportReport };
JS

cat > test/report.test.js <<'JS'
const test = require("node:test");
const assert = require("node:assert");
const { exportReport } = require("../src/exporter/report");

test("exports one line per ticket", () => {
  const rows = [{ id: 7, owner: "dana", closedAt: "2026-10-02" }];
  const csv = exportReport(rows, { footer: { text: "weekly" } });
  assert.strictEqual(csv.split("\n").length, 3);
});
JS

cat > CHANGELOG.md <<'MD'
# Changelog

## 2.3.0

- Weekly CSV export of closed tickets.
MD

git add .
git commit -q -m "feat(exporter): weekly CSV report of closed tickets"

cat > docs/adr/0004-report-footer-is-optional.md <<'MD'
# 4. The report footer is optional

Status: accepted

Callers may omit `options.footer`. When it is present it must carry a `text` string; the
exporter does not default a missing `text`.
MD
git add docs/adr
git commit -q -m "docs(adr): 0004 report footer is optional"

cat > docs/known-issues.md <<'MD'
# Known issues

- `formatDate` returns `null` for an open ticket (no `closedAt`), so the Closed cell is empty.
  Accepted for now; the CSV writer prints `null` as an empty cell.
MD
git add docs/known-issues.md
git commit -q -m "docs: known issue, formatDate returns null for open tickets"

cat > config/columns.json <<'JSON'
{ "id": "Ticket", "owner": "Owner", "closedAt": "Closed" }
JSON

cat > src/exporter/columns.js <<'JS'
const COLUMN_LABELS = require("../../config/columns.json");

function mapColumn(field) {
  return COLUMN_LABELS[field] ?? null;
}

module.exports = { mapColumn };
JS

cat > src/exporter/report.js <<'JS'
const { mapColumn } = require("./columns");
const { formatDate } = require("./dates");

function exportReport(rows, options = {}) {
  const fields = Object.keys(rows[0] || {});
  const header = fields.map((field) => mapColumn(field).toUpperCase()).join(",");
  const body = rows.map((row) =>
    fields.map((field) => (field === "closedAt" ? formatDate(row[field]) : row[field])).join(","),
  );
  const footer = options.footer ? options.footer.text.trim() : "";
  return [header, ...body, footer].join("\n");
}

module.exports = { exportReport };
JS

cat > CHANGELOG.md <<'MD'
# Changelog

## Unreleased

- Column headers now come from `config/columns.json` labels instead of the raw field names.

## 2.3.0

- Weekly CSV export of closed tickets.
MD

git add .
git commit -q -m "feat(exporter): label columns through config/columns.json"

cat > test/report-region.test.js <<'JS'
const test = require("node:test");
const assert = require("node:assert");
const { exportReport } = require("../src/exporter/report");

// Fails today: TypeError: Cannot read properties of null (reading 'toUpperCase')
test("exports the region column added for the EMEA rollout", () => {
  const rows = [
    { id: 7, owner: "dana", region: "emea", closedAt: "2026-10-02" },
    { id: 8, owner: "lee", region: "apac", closedAt: null },
  ];
  const csv = exportReport(rows, { footer: { text: "weekly" } });
  assert.match(csv, /^TICKET,OWNER,REGION,CLOSED/);
});
JS
