---
description: 'Legacy setup 6. Unattended first-time apply on a checkout where gh is installed and gh repo view resolves: no question is presented or blocked on, each decision takes its RECOMMENDED answer (github with lease_ttl_hours 24, default role labels, seeding skipped to the empty skeleton), nothing is inferred or invented, and the summary names the defaults and how to seed later. github-lease-24 reads the reply. Read-only tools, graded on the reply.'
tags: [setup, apply, unattended, hard]
max_turns: 15
timeout_seconds: 420
allowed_tools: [Read, Glob, Grep, Skill]
expected_outcome: 'With no interactive user, none of apply''s questions are presented and none blocks: not the provider/config interview, not the role-label remap offer, not the seeding offer. Each resolves to its RECOMMENDED answer silently: the binding is github with lease_ttl_hours 24 (safe because gh is installed and gh repo view resolves acme/widget in this checkout), the role-label pass keeps the defaults and writes no config.role_labels, and seeding is skipped, leaving the empty {"items": []} skeleton. No candidate inference, no per-item interview, no invented answers. The summary names the defaults taken and says the schedule can be seeded later by re-running apply --seed-schedule, or a bare apply and accepting the offer, with a user present.'
---

/work-items:setup apply

First-time bind: AGENTS.md binds no convention home, docs/conventions/work-items.yaml does not exist, no .work-item-tracker.json exists, and .github/recurring-schedule.json is absent. jq is installed; gh is installed and authenticated, and `gh repo view --json owner,name` resolves to acme/widget. .gitignore carries a docs/conventions/work-items.local.yaml line. The label set holds recurring, provenance: untrusted and capability-tier: frontier, `backfill-capability-tier-labels.sh check` reports no candidates, and no label-as-code owner is declared. This runs unattended: there is no interactive user to answer any question.

Treat the state above as what this run's reads return. No tracker, forge or shell is reachable in this session, so make no such call: say what the run does, in order, and why.
