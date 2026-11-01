#!/usr/bin/env bash
# A checkout bound to the offline local-markdown tracker holding two open raw-intake items, one
# unlabeled and one with the bare needs-triage marker, for a bare attention-view run.
set -euo pipefail

git init -q -b main
git config user.name eval
git config user.email eval@example.invalid

printf '# ledger\n\nLedger service.\n' >README.md
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
title: "CSV export drops the header row"
state: "open"
assignees: []
labels: []
type: null
parent: null
url: "file://.work-items/1.md"
created_at: "2026-10-01T08:00:00Z"
---

Running `ledger export` writes the rows but not the header line.
MD
cat >.work-items/2.md <<'MD'
---
id: "local-markdown:local/markdown#2"
number: 2
title: "Add a --since filter to ledger export"
state: "open"
assignees: []
labels: ["needs-triage"]
type: null
parent: null
url: "file://.work-items/2.md"
created_at: "2026-10-02T08:00:00Z"
---

I only want this month's entries in the export.
MD
git add README.md docs .work-items
git commit -q -m "chore: scaffold ledger"
