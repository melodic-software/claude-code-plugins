#!/usr/bin/env bash
# A checkout bound to the offline local-markdown tracker holding one open item that carries the
# raw needs-triage marker but is the work-loop lane's telemetry home: the lane config pins it as
# telemetry.issue and its body holds the lane-telemetry sentinel. Its title is operator-chosen,
# not the default "Lane telemetry: <lane>", so a title-only test misses it.
set -euo pipefail

git init -q -b main
git config user.name eval
git config user.email eval@example.invalid

printf '.work/\n' >.gitignore
printf '# ledger\n\nLedger service.\n' >README.md
mkdir -p .work-items .work/lanes
cat >.work-item-tracker.json <<'JSON'
{"schema_version": "1.0", "provider": "local-markdown", "config": {"lease_ttl_hours": 24, "storage_dir": ".work-items"}}
JSON
cat >.work/lanes/lanes.json <<'JSON'
{"lanes": [{"name": "work-loop", "stage": "work", "telemetry": {"issue": 1}}]}
JSON
cat >.work-items/1.md <<'MD'
---
id: "local-markdown:local/markdown#1"
number: 1
title: "Backlog drain board"
state: "open"
assignees: []
labels: ["needs-triage"]
type: null
parent: null
url: "file://.work-items/1.md"
created_at: "2026-10-01T08:00:00Z"
---

<!-- harness-ops:lane-telemetry marker=work-loop -->
Cycle 41: admitted 2 items, drained 1, escalated 0. Next cycle in 30 minutes.
MD
git add .gitignore README.md .work-item-tracker.json .work-items
git commit -q -m "chore: scaffold ledger"
