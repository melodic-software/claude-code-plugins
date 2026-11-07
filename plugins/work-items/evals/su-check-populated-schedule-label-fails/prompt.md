---
description: 'Legacy setup 10. check on a github binding whose committed schedule carries three rows while the recurring label is absent: the role-label probe is a hard FAIL (a seeded item would land unlabeled and go invisible to due/work), remediated through the declared label provisioning process, never gh label create ad hoc, and nothing is written. role-label-fail reads the reply. Read-only tools, graded on the reply.'
tags: [setup, check, routine]
max_turns: 15
timeout_seconds: 420
allowed_tools: [Read, Glob, Grep, Skill]
expected_outcome: 'With the schedule carrying rows, the absent recurring-maintenance label is a hard FAIL: a seeded recurring item would land unlabeled and go invisible to the next due/work pass. The remediation named is the repository''s declared label provisioning process, never an ad hoc gh label create. The row-count branch relaxes nothing here. Nothing is written and no label is created.'
---

/work-items:setup check

AGENTS.md binds no convention home. The tracker key of docs/conventions/work-items.yaml binds github with config.lease_ttl_hours 24, and no .work-item-tracker.json exists. .github/recurring-schedule.json is present and valid, carrying three items with unique ids and titles. The resolved recurring-maintenance label (recurring, no remap configured) is NOT present in the repo's label set; the label set does hold provenance: untrusted and capability-tier: frontier. jq is installed, `gh repo view --json owner,name` resolves to acme/widget, .gitignore carries a docs/conventions/work-items.local.yaml line, no personal override file exists, and both docs/conventions/work-items.yaml and the schedule are committed and not ignored.

Treat the state above as what this run's reads return. No tracker, forge or shell is reachable in this session, so make no such call: say what the run does, in order, and why.
