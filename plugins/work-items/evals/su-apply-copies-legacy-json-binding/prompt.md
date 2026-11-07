---
description: 'Legacy setup 21. Unattended apply where only the legacy .work-item-tracker.json (and its local personal override) binds the repo and docs/conventions/work-items.yaml holds only ai_disclaimer: check reports the legacy-only binding, apply adds and announces the work-items.local.yaml ignore rule, runs migrate-binding.sh to copy both layers, keeps ai_disclaimer, and leaves both JSON files unchanged for older readers. runs-migrate-binding reads the reply. Read-only tools, graded on the reply.'
tags: [setup, apply, migration, hard]
max_turns: 15
timeout_seconds: 420
allowed_tools: [Read, Glob, Grep, Skill]
expected_outcome: 'Check reports that the binding exists only in the legacy JSON file. Apply ensures a .gitignore rule covers docs/conventions/work-items.local.yaml and announces that edit, then runs migrate-binding.sh, which appends a tracker mapping to docs/conventions/work-items.yaml below ai_disclaimer and writes docs/conventions/work-items.local.yaml with the personal override''s lease_ttl_hours 6. It announces both copies and says the JSON files stay unchanged because older installed plugin versions and the repository''s own tooling may still read only them, and that later binding edits land only in the YAML. It does not delete, rewrite or ask the user to edit .work-item-tracker.json, and it keeps the copied binding rather than re-binding a provider.'
---

/work-items:setup apply

.work-item-tracker.json at the repo root binds github with config.lease_ttl_hours 24, and .work-item-tracker.local.json beside it sets config.lease_ttl_hours 6. AGENTS.md binds no convention home, and docs/conventions/work-items.yaml holds only ai_disclaimer: false. .gitignore carries a .work-item-tracker.local.json line and nothing else. jq is installed and `gh repo view --json owner,name` resolves to acme/widget. The label set holds recurring, provenance: untrusted and capability-tier: frontier, `backfill-capability-tier-labels.sh check` reports no candidates, and .github/recurring-schedule.json is absent. This runs unattended.

Treat the state above as what this run's reads return. No tracker, forge or shell is reachable in this session, so make no such call: say what the run does, in order, and why.
