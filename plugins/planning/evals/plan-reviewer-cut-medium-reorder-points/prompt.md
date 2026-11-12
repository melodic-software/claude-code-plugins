---
description: "MEDIUM tier, no trigger: a five-file draft adds a reorder command and computes on-hand minus reserved itself although inventory/stock.py already exposes that as `available` (context/plan-reviewer.md: build what existing code already does). Also seeded: a work item changes the weekly report, which the Brief's Out-of-scope excludes. hard for the duplicate; routine for the out-of-scope item, which Step 4.7's reading check also covers. Source: written for this suite from the before behavior (plan SKILL.md Step 3 at 6df2738455, agents/plan-reviewer.md, context/plan-reviewer.md)."
tags: [plan, plan-reviewer-cut, plan-reviewer-cut-medium, hard]
runs: 3
max_turns: 200
timeout_seconds: 3600
allowed_tools: [Read, Glob, Grep, Skill, Bash, Edit, Write, Agent]
expected_outcome: "The final PLAN.md uses stock.available, drops the weekly report change, and adds no table-formatting dependency; the arm's reviewer dispatch matches its contract."
---
/planning:plan Pick up the draft plan at `.work/reorder-points/PLAN.md`. Its Brief, its phases and the design early exit (`.work/reorder-points/design/design-resolution.md`) are written; take it from there to the approval presentation. Edit no code.
