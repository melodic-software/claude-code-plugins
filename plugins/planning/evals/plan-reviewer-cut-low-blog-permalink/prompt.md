---
description: "LOW tier, no trigger: a draft adds post permalinks and writes its own slug helper although blog/text.py already has `slugify`, which AC2's accent folding needs (context/plan-reviewer.md: build what existing code already does). Also seeded: a Behavior item that names a file and a step instead of an observable claim (agents/plan-reviewer.md third check). hard: the duplicate is visible only by reading code the plan never cites. Source: written for this suite from the before behavior (plan SKILL.md Step 3 at 6df2738455, agents/plan-reviewer.md, context/plan-reviewer.md)."
tags: [plan, plan-reviewer-cut, plan-reviewer-cut-low, hard]
runs: 3
max_turns: 150
timeout_seconds: 2700
allowed_tools: [Read, Glob, Grep, Skill, Bash, Edit, Write, Agent]
expected_outcome: "The final PLAN.md reuses blog.text.slugify, rewrites the file-naming Behavior item as a claim, and does not change blog/models.py; the arm's reviewer dispatch matches its contract."
---
/planning:plan Pick up the draft plan at `.work/post-permalink/PLAN.md`. Its Brief, its phases and the design early exit (`.work/post-permalink/design/design-resolution.md`) are written; take it from there to the approval presentation. Edit no code.
