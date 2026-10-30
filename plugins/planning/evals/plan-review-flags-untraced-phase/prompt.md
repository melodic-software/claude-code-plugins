---
description: "Outcome case: a draft plan's Brief has two acceptance criteria about a 404 response and an Out-of-scope list naming only pagination. Phase 1 covers both criteria; Phase 2 adds a response cache that serves neither and is not listed as Out-of-scope. The plan review passes when it flags Phase 2 for cutting or as an Open Decision, without flagging Phase 1"
tags: [plan, plan-reviewer, outcome, trace-or-cut, scaffold]
runs: 3
max_turns: 30
timeout_seconds: 480
allowed_tools: [Read, Glob, Grep, Skill, Bash, Agent, Write, Edit]
expected_outcome: "The reported plan-review findings flag Phase 2 (the response cache) as serving neither acceptance criterion, note that its absence from the Out-of-scope list does not clear it, and give the action to cut it or surface it as an Open Decision for the user. Phase 1 is not flagged as untraced. No .py file is written or edited"
---

/planning:plan review

The draft plan for topic `orders-404` is at `.work/orders-404/PLAN.md`. Review it for completeness and alignment with its Brief, show me the findings, then stop. Don't edit any file.
