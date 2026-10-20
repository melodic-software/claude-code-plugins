---
description: "Outcome case: a draft plan writes one 30-day retention window into the cleanup job, the admin API view and the operator docs as three literals, while the repo keeps shared limits in app/settings.py. The plan stress-test passes when its findings flag the spread fact"
tags: [plan, plan-reviewer, outcome, principles, dry, scaffold]
runs: 3
max_turns: 30
timeout_seconds: 900
allowed_tools: [Read, Glob, Grep, Skill, Bash, Agent, Write, Edit]
expected_outcome: "The reported plan-review findings flag that the 30-day retention value is placed in several files (app/cleanup/job.py, app/api/settings_view.py, docs/operations.md) with no single home, and point at one source such as app/settings.py. No .py file is written or edited"
---

/planning:plan

The draft plan for topic `log-retention` is at `.work/log-retention/PLAN.md`. Run its Step 3 plan stress-test on that draft and show me the findings, then stop. Don't edit any file.
