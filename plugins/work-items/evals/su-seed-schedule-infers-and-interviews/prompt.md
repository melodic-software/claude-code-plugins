---
description: 'Legacy setup 1. apply --seed-schedule on a bound github repo whose committed schedule is an empty {"items": []}: the flag is the opt-in (no re-offer), the run summarizes the schedule, infers candidates only from package.json, the eslint config and the CI workflow (no security item), and interviews one item at a time with recommended values marked. manifest-candidate-quarterly reads the reply. Read-only tools, graded on the reply.'
tags: [setup, apply, seeding, routine]
max_turns: 15
timeout_seconds: 420
allowed_tools: [Read, Glob, Grep, Skill]
expected_outcome: 'The explicit --seed-schedule argument opts in to the seeding pass, so it runs without asking again: the run reads .github/recurring-schedule.json and reports it carries zero rows, then infers candidates from what the repo contains (package.json, eslint.config.js, .github/workflows/ci.yml), each with a recommended cadence (quarterly for each), and interviews one item at a time with recommended field values marked before moving on. It proposes no security-review item, since the repo gives no signal for one, and writes only what the operator accepts.'
---

/work-items:setup apply --seed-schedule

Today is 2026-11-07. AGENTS.md binds no convention home. The tracker key of docs/conventions/work-items.yaml binds github with config.lease_ttl_hours 24 and no config.role_labels; no .work-item-tracker.json or .work-item-tracker.local.json exists. jq is installed and `gh repo view --json owner,name` resolves to acme/widget. .gitignore carries a docs/conventions/work-items.local.yaml line. The label set holds recurring, provenance: untrusted and capability-tier: frontier, `backfill-capability-tier-labels.sh check` reports no candidates, and no label-as-code owner is declared. .github/recurring-schedule.json is committed and carries zero rows ({"items": []}). The repo contains package.json, eslint.config.js and .github/workflows/ci.yml; it has no SECURITY.md and no auth or secrets-handling code. An interactive user is present, accepts every RECOMMENDED answer, and accepts each proposed item with its recommended values.

Treat the state above as what this run's reads return. No tracker, forge or shell is reachable in this session, so make no such call: say what the run does, in order, and why.
