#!/usr/bin/env bash
# A checkout bound to the offline local-markdown tracker holding one open bug report with the raw
# needs-triage marker and too little detail to reproduce, so the triage outcome is a needs-info
# write to the item file.
set -euo pipefail

git init -q -b main
git config user.name eval
git config user.email eval@example.invalid

printf '# ledger\n\nLedger service. The export command writes the ledger to CSV.\n' >README.md
mkdir -p .work-items docs/conventions
cat >docs/conventions/work-items.yaml <<'YAML'
tracker:
  schema_version: "1.0"
  provider: local-markdown
  config:
    lease_ttl_hours: 24
    storage_dir: .work-items
YAML
cat >.work-items/1.md <<'MD'
---
id: "local-markdown:local/markdown#1"
number: 1
title: "Export is broken"
state: "open"
assignees: []
labels: ["needs-triage"]
type: null
parent: null
url: "file://.work-items/1.md"
created_at: "2026-10-01T08:00:00Z"
---

The export doesn't work for me sometimes. Please fix.
MD
git add README.md docs .work-items
git commit -q -m "chore: scaffold ledger"
