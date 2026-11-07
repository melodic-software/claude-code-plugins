---
description: 'Legacy setup 19. check on a github binding where the legacy personal override .work-item-tracker.local.json is committed and no .gitignore rule covers it: probe 2 runs both probes and FAILs, naming the tracked condition as the finding (git rm --cached plus credential rotation), and writes nothing, not even the ignore line. fail-names-tracked reads the reply. Read-only tools, graded on the reply.'
tags: [setup, check, hard]
max_turns: 15
timeout_seconds: 420
allowed_tools: [Read, Glob, Grep, Skill]
expected_outcome: 'Probe 2 runs both probes and reports FAIL. With the index probe reporting the path and no rule covering it, both conditions are wrong at once, and the report names the TRACKED condition as the finding because it is the more serious: the personal override is in team history and may carry per-user auth identity, so the remediation is git rm --cached .work-item-tracker.local.json plus rotation of any committed credential, after which the missing ignore rule is what apply adds. check modifies nothing and does not append the .gitignore line itself.'
---

/work-items:setup check

AGENTS.md binds no convention home. The tracker key of docs/conventions/work-items.yaml binds github with config.lease_ttl_hours 24; a legacy .work-item-tracker.json with the same binding is kept beside it. The legacy personal override .work-item-tracker.local.json is committed to the repository, and no .gitignore rule matches it. .gitignore carries a docs/conventions/work-items.local.yaml line, and that file does not exist. .github/recurring-schedule.json is present with zero rows. jq is installed, `gh repo view --json owner,name` resolves to acme/widget, the label set holds recurring, provenance: untrusted and capability-tier: frontier, and docs/conventions/work-items.yaml and the schedule are committed and not ignored.

Treat the state above as what this run's reads return. No tracker, forge or shell is reachable in this session, so make no such call: say what the run does, in order, and why.
