---
description: 'Legacy setup 11. check on a github binding whose schedule has a null items key while the recurring label is absent: schedule validity FAILs and stays the gate, and the role-label probe, with no readable row count, is INFO naming that FAIL, neither a zero-row INFO nor a label FAIL. Nothing is written. role-label-info-names-validity reads the reply. Read-only tools, graded on the reply.'
tags: [setup, check, hard]
max_turns: 15
timeout_seconds: 420
allowed_tools: [Read, Glob, Grep, Skill]
expected_outcome: 'A schedule that does not parse as the {"items": [ ... ]} root is a validity FAIL, and that FAIL is the gate. It is not read as a zero-row schedule: the role-label probe has no readable row count to branch on, so it reports INFO naming the validity FAIL as the reason, neither downgrading that FAIL nor raising the at-least-one-row label FAIL on a guess. Nothing is written and no label is created.'
---

/work-items:setup check

AGENTS.md binds no convention home. The tracker key of docs/conventions/work-items.yaml binds github with config.lease_ttl_hours 24, and no .work-item-tracker.json exists. .github/recurring-schedule.json is present, but its root has a null items key ({"items": null}). The resolved recurring-maintenance label (recurring, no remap configured) is NOT present in the repo's label set; the label set does hold provenance: untrusted and capability-tier: frontier. jq is installed, `gh repo view --json owner,name` resolves to acme/widget, .gitignore carries a docs/conventions/work-items.local.yaml line, no personal override file exists, and both docs/conventions/work-items.yaml and the schedule are committed and not ignored.

Treat the state above as what this run's reads return. No tracker, forge or shell is reachable in this session, so make no such call: say what the run does, in order, and why.
