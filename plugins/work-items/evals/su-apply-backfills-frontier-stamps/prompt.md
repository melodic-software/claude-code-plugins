---
description: 'Legacy setup 15. Attended apply on a github binding where capability-tier: frontier exists and the backfill check finds two open issues with legacy frontier-tier body stamps but no label: after the axis pass, the run reports both candidates, offers the backfill, runs backfill-capability-tier-labels.sh apply on acceptance (no re-triage), and reports two labeled. backfill-apply reads the reply. Read-only tools, graded on the reply.'
tags: [setup, apply, labels, routine]
max_turns: 15
timeout_seconds: 420
allowed_tools: [Read, Glob, Grep, Skill]
expected_outcome: 'After the capability-tier axis pass confirms the label exists, setup runs the legacy backfill pass: it reports #31 and #34 from backfill-capability-tier-labels.sh check, offers to apply capability-tier: frontier to each (RECOMMENDED: apply all), and on acceptance runs backfill-capability-tier-labels.sh apply, confirming the two items labeled match the check output. It does not rely on triage to re-stamp already-triaged items.'
---

/work-items:setup apply

AGENTS.md binds no convention home. The tracker key of docs/conventions/work-items.yaml binds github with config.lease_ttl_hours 24 and no config.role_labels; no .work-item-tracker.json exists. jq is installed and `gh repo view --json owner,name` resolves to acme/widget. .gitignore carries a docs/conventions/work-items.local.yaml line. The label set holds recurring, provenance: untrusted and capability-tier: frontier, and no label-as-code owner is declared. `backfill-capability-tier-labels.sh check` reports two open issues, #31 and #34, whose bodies carry legacy frontier-tier stamps but lack the label. .github/recurring-schedule.json is committed and carries zero rows. An interactive user is present, accepts every RECOMMENDED answer, accepts the backfill offer, and answers "skip" to the seeding offer; the backfill apply run labels both items.

Treat the state above as what this run's reads return. No tracker, forge or shell is reachable in this session, so make no such call: say what the run does, in order, and why.
