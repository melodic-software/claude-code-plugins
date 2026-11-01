#!/usr/bin/env bash
# A checkout bound to the offline local-markdown tracker whose repository file turns on the stale
# reporter-info setting at 14 days. Item #1 carries needs-reporter-info; its last triage note asked
# the reporter for details months ago and the reporter never replied, so it is a close candidate.
# Item #2 is just as stale, but the invocation states its reporter holds write access, so the
# write-access filter keeps it off the list.
set -euo pipefail

git init -q -b main
git config user.name eval
git config user.email eval@example.invalid

printf '.work/\n' >.gitignore
printf '# ledger\n\nLedger service.\n' >README.md
mkdir -p .work-items docs/conventions
cat >.work-item-tracker.json <<'JSON'
{"schema_version": "1.0", "provider": "local-markdown", "config": {"lease_ttl_hours": 24, "storage_dir": ".work-items"}}
JSON
cat >docs/conventions/work-items.yaml <<'YAML'
triage_stale_reporter_info_days: 14
YAML
cat >.work-items/1.md <<'MD'
---
id: "local-markdown:local/markdown#1"
number: 1
title: "Export sometimes hangs"
state: "open"
assignees: []
labels: ["needs-reporter-info"]
type: null
parent: null
url: "file://.work-items/1.md"
created_at: "2026-01-05T08:00:00Z"
---

Reported by dana-r. The export hangs now and then; no steps given.

## Comments

- 2026-01-06T09:00:00Z, triage (maintainer, write access): Which export format, and how large is
  the file when it hangs? Please share the steps that lead to the hang.
MD
cat >.work-items/2.md <<'MD'
---
id: "local-markdown:local/markdown#2"
number: 2
title: "Invoice totals round wrong"
state: "open"
assignees: []
labels: ["needs-reporter-info"]
type: null
parent: null
url: "file://.work-items/2.md"
created_at: "2026-01-07T08:00:00Z"
---

Reported by lee-m. Some invoice totals are off by a cent; no example given.

## Comments

- 2026-01-08T09:00:00Z, triage: Which invoice, and what total did you expect? Please share one
  example that rounds wrong.
MD
git add .gitignore README.md .work-item-tracker.json docs .work-items
git commit -q -m "chore: scaffold ledger"
