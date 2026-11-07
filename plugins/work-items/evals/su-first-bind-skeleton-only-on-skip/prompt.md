---
description: 'Legacy setup 5. Attended first-time apply where the user answers skip to the seeding offer: the run binds github, runs the role-label pass right after the bind, offers seeding once as a yes/no with skip RECOMMENDED, writes only the empty {"items": []} skeleton with no inference or interview, reports the missing recurring label as informational at zero rows, and points at apply --seed-schedule. skip-recommended reads the reply. Read-only tools, graded on the reply.'
tags: [setup, apply, first-bind, routine]
max_turns: 15
timeout_seconds: 420
allowed_tools: [Read, Glob, Grep, Skill]
expected_outcome: 'On a first-time bind with no schedule rows, a bare apply writes only the minimum viable config: the provider binding, the role-label pass, and the empty {"items": []} skeleton that stops due/recheck/work degrading to "no recurring schedule configured". It offers seeding exactly once as a single yes/no with skip marked RECOMMENDED; on skip it runs no candidate inference and no per-item interview, and says the schedule can be bulk-seeded later by re-running apply or apply --seed-schedule. The role-label pass still runs as step 2, anchored right after the bind, and with zero rows the missing recurring label is informational rather than gating the bind.'
---

/work-items:setup apply

First-time bind: AGENTS.md binds no convention home, docs/conventions/work-items.yaml does not exist, no .work-item-tracker.json exists, and .github/recurring-schedule.json is absent. jq is installed, gh is installed, and `gh repo view --json owner,name` resolves to acme/widget. .gitignore carries a docs/conventions/work-items.local.yaml line. The label set holds provenance: untrusted and capability-tier: frontier but NOT recurring, `backfill-capability-tier-labels.sh check` reports no candidates, and no label-as-code owner is declared. An interactive user is present, accepts every RECOMMENDED answer (github with lease_ttl_hours 24, default role labels, no won't-do labels), and answers "skip" to the seeding offer.

Treat the state above as what this run's reads return. No tracker, forge or shell is reachable in this session, so make no such call: say what the run does, in order, and why.
