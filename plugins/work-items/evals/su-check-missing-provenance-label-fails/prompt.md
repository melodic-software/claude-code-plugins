---
description: 'Legacy setup 13. check on a github binding whose label listing returns no provenance: labels: probe 7 FAILs on the missing provenance: untrusted label, remediated by /work-items:setup apply or the label-as-code owner, never gh label create ad hoc, and nothing is written. provenance-fail reads the reply. Read-only tools, graded on the reply.'
tags: [setup, check, routine]
max_turns: 15
timeout_seconds: 420
allowed_tools: [Read, Glob, Grep, Skill]
expected_outcome: 'Probe 7 reports FAIL for the missing provenance: untrusted label, since triage cannot mark an untrusted item until it exists. Remediation is /work-items:setup apply on repos without label-as-code, or the repo''s declared label-as-code owner. Never gh label create ad hoc when label-as-code owns writes. Nothing is written.'
---

/work-items:setup check

AGENTS.md binds no convention home. The tracker key of docs/conventions/work-items.yaml binds github with config.lease_ttl_hours 24, and no .work-item-tracker.json exists. `gh label list` returns no provenance: labels; it does return recurring and capability-tier: frontier. .github/recurring-schedule.json is present with zero rows ({"items": []}). jq is installed, `gh repo view --json owner,name` resolves to acme/widget, .gitignore carries a docs/conventions/work-items.local.yaml line, no personal override file exists, and both docs/conventions/work-items.yaml and the schedule are committed and not ignored.

Treat the state above as what this run's reads return. No tracker, forge or shell is reachable in this session, so make no such call: say what the run does, in order, and why.
