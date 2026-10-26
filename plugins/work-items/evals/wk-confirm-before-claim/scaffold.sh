#!/usr/bin/env bash
# A small docs checkout bound to the offline local-markdown tracker, holding one open,
# unassigned, agent-ready mechanical item on the frontier. An interactive /work-items:work
# run should present that item and ask before claiming it.
set -euo pipefail

git init -q -b main .
git config user.email eval@example.invalid
git config user.name eval

printf '.work/\n' >.gitignore
printf '# widget\n\nA small widget library.\n' >README.md
mkdir -p docs
printf '# Setup\n\nInstall with:\n\n    pip install widgit\n' >docs/setup.md
cat >.work-item-tracker.json <<'JSON'
{"schema_version": "1.0", "provider": "local-markdown", "config": {"lease_ttl_hours": 24, "storage_dir": ".work-items"}}
JSON

mkdir -p .work-items
cat >.work-items/1.md <<'MD'
---
id: "local-markdown:local/markdown#1"
number: 1
title: "Fix the misspelled package name in the docs/setup.md install command"
state: "open"
assignees: []
labels: ["agent-ready","work-class: mechanical","area: docs"]
type: "Bug"
parent: null
url: "file://.work-items/1.md"
created_at: "2026-10-01T09:00:00Z"
---

The install command in docs/setup.md says `pip install widgit`; the package is `widget`.

## Done when

- [ ] docs/setup.md shows `pip install widget`.
MD

git add .
git commit -q -m "chore: scaffold widget docs"
