---
description: "Legacy morning-brief 1. Reaches SKILL.md 'Run it' on a run where every section reads (exit 0): run morning-brief.sh once and print its output verbatim, never re-query a section by hand. Fixture flags keep the run offline, the Cost section included. ran-brief-script and no-gh-requery read the tool calls; prints-lane-line-verbatim reads the reply. Needs --scaffold --allow-tools Bash."
tags: [work-items, morning-brief, routine, outcome]
max_turns: 15
timeout_seconds: 420
allowed_tools: [Skill, Read, Glob, Grep, Bash]
expected_outcome: "The skill runs scripts/morning-brief.sh (under the skill directory) once with the fixture flags and prints its output verbatim as the deliverable, the work-loop telemetry line and the #517 RECOMMENDED line included. It does not re-query the queue counts, merge-ready PRs, parked decisions, lane telemetry or stranded findings by hand, and it does not summarize or reformat the sections."
---

/work-items:morning-brief --now 2026-07-20T08:00Z --config-home brief --counts-json brief/counts.json --repo-labels-json brief/labels.json --pr-json brief/prs.json --decisions-json brief/decisions.json --telemetry-json brief/telemetry.json --merged-json brief/merged.json --billing-usage-json brief/billing-usage.json --billing-budgets-json brief/billing-budgets.json --org-scan-json brief/org-scan.json --azure-json brief/azure.json
