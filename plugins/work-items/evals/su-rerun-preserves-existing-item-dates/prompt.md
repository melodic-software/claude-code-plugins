---
description: 'Legacy setup 2. apply re-run on a bound repo whose schedule carries three dated rows, one overdue, plus one new item the operator accepts: existing last_checked and next_due stay as-is (setup does no maintenance), the overdue row keeps its date, and the new row seeds today and today plus the cadence. overdue-row-preserved reads the reply. Read-only tools, graded on the reply.'
tags: [setup, apply, schedule, hard]
max_turns: 15
timeout_seconds: 420
allowed_tools: [Read, Glob, Grep, Skill]
expected_outcome: 'Re-running against an existing schedule preserves each existing item''s last_checked and next_due as-is, since setup seeds but performs no maintenance and never advances the cadence clock; next_due is recomputed only on an explicit reschedule or cadence change, and last_checked is never reset to today. The overdue ci-pin-review keeps next_due 2026-09-29, so it stays in the due/work tiers. The new lint-config-review row seeds last_checked 2026-11-07 and next_due 2026-12-07 (today plus 30 days for monthly).'
---

/work-items:setup apply

Today is 2026-11-07. AGENTS.md binds no convention home. The tracker key of docs/conventions/work-items.yaml binds github with config.lease_ttl_hours 24 and no config.role_labels; no .work-item-tracker.json exists. jq is installed and `gh repo view --json owner,name` resolves to acme/widget. .gitignore carries a docs/conventions/work-items.local.yaml line. The label set holds recurring, provenance: untrusted and capability-tier: frontier, `backfill-capability-tier-labels.sh check` reports no candidates, and no label-as-code owner is declared. The repo contains package.json, eslint.config.js and .github/workflows/ci.yml.

.github/recurring-schedule.json is committed and carries three items:

- dependency-review, quarterly, last_checked 2026-09-01, next_due 2026-11-30
- ci-pin-review, quarterly, last_checked 2026-07-01, next_due 2026-09-29 (overdue)
- security-review, semi-annual, last_checked 2026-06-01, next_due 2026-11-28

An interactive user is present and accepts every RECOMMENDED answer. In the interview the user keeps all three existing rows exactly as they are (no reschedule, no cadence change) and accepts one new item, lint-config-review (title Review linter config against current defaults, cadence monthly).

Treat the state above as what this run's reads return. No tracker, forge or shell is reachable in this session, so make no such call: say what the run does, in order, and why.
