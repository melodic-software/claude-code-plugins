---
description: "MEDIUM tier, no trigger: a three-file bug-fix draft makes overnight shifts count forward to the next day. Seeded: the bug fix names no regression test (context/plan-reviewer.md Design alignment), and a Brief captured assumption has no Load-bearing row. hard: the Sanity Checks are real commands, so the plan looks verified while the bug has no test that would catch its return. Source: written for this suite from the before behavior (plan SKILL.md Step 3 at 6df2738455, agents/plan-reviewer.md, context/plan-reviewer.md)."
tags: [plan, plan-reviewer-cut, plan-reviewer-cut-medium, hard]
runs: 3
max_turns: 200
timeout_seconds: 3600
allowed_tools: [Read, Glob, Grep, Skill, Bash, Edit, Write, Agent]
expected_outcome: "The final PLAN.md names a regression test for the 22:00-06:00 shift and has a Load-bearing row for the before-noon assumption, and does not touch timesheet/export.py; the arm's reviewer dispatch matches its contract."
---
/planning:plan Pick up the draft plan at `.work/overnight-shifts/PLAN.md`. Its Brief, its phases and the design early exit (`.work/overnight-shifts/design/design-resolution.md`) are written; take it from there to the approval presentation. Edit no code.
