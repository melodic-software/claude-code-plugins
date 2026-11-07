---
description: 'Legacy setup 3. First-time apply whose invocation asks for a seeded schedule: the request is the opt-in, the run binds github, infers candidates, and before writing .github/recurring-schedule.json ({"items": [...]} root, consumer tree only) finds the operator''s custom item duplicating a candidate''s title and stops to prompt; it confirms the recurring label via the provider. title-collision-stops reads the reply. Read-only tools, graded on the reply.'
tags: [setup, apply, schedule, hard]
max_turns: 15
timeout_seconds: 420
allowed_tools: [Read, Glob, Grep, Skill]
expected_outcome: 'The request to seed is the opt-in. After binding github, the run infers the dependency-manifest and CI candidates, and before writing verifies every final id and title is unique across the array: the custom item''s title collides with the dependency-manifest candidate''s, so it stops and prompts (merge, replace, or pick a unique value) rather than writing a duplicate; the operator drops the custom item. It confirms the recurring label exists via the bound provider''s label listing as a load-bearing check, and writes the accepted rows to the consumer''s tracked project-root .github/recurring-schedule.json with the {"items": [ ... ]} root, never into the plugin directory or plugin data directory.'
---

/work-items:setup apply

Seed a sensible recurring schedule for this repo.

First-time bind: AGENTS.md binds no convention home, docs/conventions/work-items.yaml does not exist, no .work-item-tracker.json exists, and .github/recurring-schedule.json is absent. jq is installed, gh is installed, and `gh repo view --json owner,name` resolves to acme/widget. .gitignore carries a docs/conventions/work-items.local.yaml line. The label set holds recurring, provenance: untrusted and capability-tier: frontier, `backfill-capability-tier-labels.sh check` reports no candidates, and no label-as-code owner is declared. The repo contains package.json and .github/workflows/ci.yml, and nothing else that signals a recurring item.

An interactive user is present and accepts every RECOMMENDED answer (github with lease_ttl_hours 24, default role labels, no won't-do labels) and each inferred candidate as proposed. After the candidates, the user names one custom item, id deps-refresh, whose title is exactly the title proposed for the dependency-manifest candidate. When told of any collision, the user drops the custom item.

Treat the state above as what this run's reads return. No tracker, forge or shell is reachable in this session, so make no such call: say what the run does, in order, and why.
