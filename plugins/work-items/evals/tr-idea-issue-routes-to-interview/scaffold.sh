#!/usr/bin/env bash
# A checkout bound to the offline local-markdown tracker holding one open idea issue: a feature
# request carrying the raw needs-triage marker that names something to build but says nothing
# about what it is for. The checkout also holds source code an exploring triage would search.
set -euo pipefail

git init -q -b main
git config user.name eval
git config user.email eval@example.invalid

printf '.work/\n' >.gitignore
printf '# ledger\n\nLedger service.\n' >README.md
mkdir -p .work-items src
cat >src/export.js <<'JS'
export function exportCsv(rows) {
  return rows.map((row) => row.join(",")).join("\n");
}
JS
cat >.work-item-tracker.json <<'JSON'
{"schema_version": "1.0", "provider": "local-markdown", "config": {"lease_ttl_hours": 24, "storage_dir": ".work-items"}}
JSON
cat >.work-items/1.md <<'MD'
---
id: "local-markdown:local/markdown#1"
number: 1
title: "Add a plugin system"
state: "open"
assignees: []
labels: ["needs-triage"]
type: null
parent: null
url: "file://.work-items/1.md"
created_at: "2026-10-01T08:00:00Z"
---

We should add a plugin system to the ledger.
MD
git add .gitignore README.md src .work-item-tracker.json .work-items
git commit -q -m "chore: scaffold ledger"
