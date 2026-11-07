---
description: 'Legacy setup 8. Unattended apply on a repo already bound to local-markdown while gh works: the read-first keep-it recommendation resolves silently, so the binding and config stay unchanged and github is not bound; the role-label pass keeps defaults, seeding is skipped and the empty skeleton is written. keeps-local-markdown reads the reply. Read-only tools, graded on the reply.'
tags: [setup, apply, unattended, hard]
max_turns: 15
timeout_seconds: 420
allowed_tools: [Read, Glob, Grep, Skill]
expected_outcome: 'The unattended github default applies only where there is no binding to preserve. Here a valid one exists, so the read-first recommendation, keep it, is what the unattended rule resolves to silently: the repo stays on local-markdown with storage_dir .work-items, and nothing in the binding is rewritten. A working gh does not make github the answer, since re-binding is a switch-providers decision no default can stand in for. The run continues past the bind: the role-label pass keeps its defaults, the label passes report INFO for a provider with no label listing, seeding is skipped, and the empty {"items": []} skeleton is written.'
---

/work-items:setup apply

AGENTS.md binds no convention home. The tracker key of docs/conventions/work-items.yaml binds local-markdown with config.lease_ttl_hours 24 and config.storage_dir .work-items, and no .work-item-tracker.json exists. .github/recurring-schedule.json is absent. jq is installed; gh is installed and authenticated, and `gh repo view --json owner,name` resolves to acme/widget. .gitignore carries a docs/conventions/work-items.local.yaml line, and the binding is committed. This runs unattended: there is no interactive user to answer any question.

Treat the state above as what this run's reads return. No tracker, forge or shell is reachable in this session, so make no such call: say what the run does, in order, and why.
