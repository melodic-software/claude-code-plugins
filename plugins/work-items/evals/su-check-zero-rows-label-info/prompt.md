---
description: 'Legacy setup 9. check on a github binding whose committed schedule is a valid empty {"items": []} while the recurring label is absent: the role-label probe keys on the row count and reports INFO (label needed before seeding), the empty schedule is INFO pointing at apply --seed-schedule, and nothing is written. role-label-info reads the reply. Read-only tools, graded on the reply.'
tags: [setup, check, routine]
max_turns: 15
timeout_seconds: 420
allowed_tools: [Read, Glob, Grep, Skill]
expected_outcome: 'The role-label probe branches on the schedule''s row count, not on whether the file exists. With zero rows no recurring item can be created, so the absent recurring label is INFO, noting it must exist before the schedule is ever seeded, matching apply step 9''s treatment of the same state. The present-but-empty schedule is INFO from the validity probe, pointing at apply --seed-schedule. Nothing is written and no label is created.'
---

/work-items:setup check

AGENTS.md binds no convention home. The tracker key of docs/conventions/work-items.yaml binds github with config.lease_ttl_hours 24, and no .work-item-tracker.json exists. .github/recurring-schedule.json is present and valid, carrying zero rows ({"items": []}). The resolved recurring-maintenance label (recurring, no remap configured) is NOT present in the repo's label set; the label set does hold provenance: untrusted and capability-tier: frontier. jq is installed, `gh repo view --json owner,name` resolves to acme/widget, .gitignore carries a docs/conventions/work-items.local.yaml line, no personal override file exists, and both docs/conventions/work-items.yaml and the schedule are committed and not ignored.

Treat the state above as what this run's reads return. No tracker, forge or shell is reachable in this session, so make no such call: say what the run does, in order, and why.
