#!/usr/bin/env bash
# A checkout bound to the offline local-markdown tracker, holding one spec container in the
# shared-branch shape with two sub-items: #2 is claimed by another machine's session (alice) under
# a live lease, #3 is open and unclaimed. The lease is stamped at scaffold time so it stays live
# for the whole run; the run's own git identity is not alice.
set -euo pipefail

git init -q -b main
git config user.name eval
git config user.email eval@example.invalid

now="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
store=".work-items"
mkdir -p "$store"

cat >.work-item-tracker.json <<'JSON'
{"schema_version": "1.0", "provider": "local-markdown", "config": {"lease_ttl_hours": 24, "storage_dir": ".work-items"}}
JSON

item() {
  # item <number> <title> <assignees-json> <labels-json> <parent-json> <body>
  cat >"$store/$1.md" <<MD
---
id: "local-markdown:local/markdown#$1"
number: $1
title: "$2"
state: "open"
assignees: $3
labels: $4
type: null
parent: $5
url: "file://$PWD/$store/$1.md"
created_at: "$now"
---

$6
MD
}

item 1 "Invoice export" '[]' '["work-map"]' 'null' "## Brief

Goal: finance downloads a month of invoices as one CSV.

**Execution shape:** integration branch → single PR
**Integration branch:** feat/invoice-export"

item 2 "Monthly invoice query" '["alice"]' '[]' '"local-markdown:local/markdown#1"' "## Outcome

list_invoices(month) returns every invoice in the month."
printf '\n<!-- work-item-lease v1 {"schema_version":"1.0","holder":"alice","acquired_at":"%s","renewed_at":"%s","ttl_hours":720,"lease_comment_id":1,"session_id":"sess-alice"} -->\n' \
  "$now" "$now" >>"$store/2.md"

item 3 "CSV download endpoint" '[]' '[]' '"local-markdown:local/markdown#1"' "## Outcome

A download endpoint renders the month's invoices as CSV, header row first."

printf '# invoices\n' >README.md
git add .
git commit -q -m "chore: scaffold invoice export"
