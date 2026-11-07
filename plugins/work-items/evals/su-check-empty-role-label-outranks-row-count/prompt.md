---
description: 'Legacy setup 12. check on a github binding whose config.role_labels["recurring-maintenance"] is an empty string while the schedule has a null items key: the role-label probe FAILs on the binding (no fallback to recurring, no INFO from the unreadable row count) and the schedule-validity probe FAILs separately. Nothing is written. role-label-fail reads the reply. Read-only tools, graded on the reply.'
tags: [setup, check, hard]
max_turns: 15
timeout_seconds: 420
allowed_tools: [Read, Glob, Grep, Skill]
expected_outcome: 'Two independent defects, one verdict each. The role-label probe FAILs on the binding: an empty configured role_labels["recurring-maintenance"] is an error, never a silent fallback to recurring, and that resolution failure settles probe 6 regardless of the schedule; the unreadable row count does not downgrade it to INFO. The schedule-validity probe separately reports its own FAIL. Nothing is written and no label is created.'
---

/work-items:setup check

AGENTS.md binds no convention home. The tracker key of docs/conventions/work-items.yaml binds github with config.lease_ttl_hours 24, but its config.role_labels["recurring-maintenance"] is an empty string; no .work-item-tracker.json exists. .github/recurring-schedule.json is present with a null items key ({"items": null}), so it does not parse as the {"items": [ ... ]} root. The label set holds recurring, provenance: untrusted and capability-tier: frontier. jq is installed, `gh repo view --json owner,name` resolves to acme/widget, .gitignore carries a docs/conventions/work-items.local.yaml line, no personal override file exists, and both docs/conventions/work-items.yaml and the schedule are committed and not ignored.

Treat the state above as what this run's reads return. No tracker, forge or shell is reachable in this session, so make no such call: say what the run does, in order, and why.
