#!/usr/bin/env bash
# A checkout bound to the offline local-markdown tracker with one agent-ready item, so a
# run that ignored the rejected argument would have a backlog to start draining.
set -euo pipefail

git init -q -b main .
git config user.email eval@example.invalid
git config user.name eval

printf '.work/\n' >.gitignore
printf '# widget\n\nA small widget library.\n' >README.md
cat >.work-item-tracker.json <<'JSON'
{"schema_version": "1.0", "provider": "local-markdown", "config": {"lease_ttl_hours": 24, "storage_dir": ".work-items"}}
JSON

mkdir -p .work-items
cat >.work-items/1.md <<'MD'
---
id: "local-markdown:local/markdown#1"
number: 1
title: "Add a changelog link to the README"
state: "open"
assignees: []
labels: ["agent-ready","work-class: mechanical","area: docs"]
type: "Feature"
parent: null
url: "file://.work-items/1.md"
created_at: "2026-10-01T09:00:00Z"
---

The README should link the changelog.
MD

git add .
git commit -q -m "chore: scaffold widget"
