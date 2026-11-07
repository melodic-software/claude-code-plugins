---
description: 'Legacy setup 14. check on a github binding whose label listing returns no capability-tier: labels: probe 8 FAILs on the missing capability-tier: frontier label (triage cannot stamp the frontier quota guard, the work-loop reader fails closed to general tier), remediated by /work-items:setup apply or the label-as-code owner, never ad hoc. Nothing is written. capability-tier-fail reads the reply. Read-only tools, graded on the reply.'
tags: [setup, check, routine]
max_turns: 15
timeout_seconds: 420
allowed_tools: [Read, Glob, Grep, Skill]
expected_outcome: 'Probe 8 reports FAIL for the missing capability-tier: frontier label: triage cannot stamp the frontier-tier quota guard and the work-loop reader fails closed to general tier until it exists. Remediation is /work-items:setup apply on repos without label-as-code, or the repo''s declared label-as-code owner. Never gh label create ad hoc when label-as-code owns writes. Nothing is written.'
---

/work-items:setup check

AGENTS.md binds no convention home. The tracker key of docs/conventions/work-items.yaml binds github with config.lease_ttl_hours 24, and no .work-item-tracker.json exists. `gh label list` returns no capability-tier: labels; it does return recurring and provenance: untrusted. .github/recurring-schedule.json is present with zero rows ({"items": []}). jq is installed, `gh repo view --json owner,name` resolves to acme/widget, .gitignore carries a docs/conventions/work-items.local.yaml line, no personal override file exists, and both docs/conventions/work-items.yaml and the schedule are committed and not ignored.

Treat the state above as what this run's reads return. No tracker, forge or shell is reachable in this session, so make no such call: say what the run does, in order, and why.
