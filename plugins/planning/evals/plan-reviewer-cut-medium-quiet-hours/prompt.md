---
description: "MEDIUM tier, no trigger: a five-file draft holds non-critical alerts during quiet hours. Seeded: a Behavior item names a file and a step (agents/plan-reviewer.md third check), and AC3 (held alerts reach the morning digest) is claimed through B3 while no work item touches alerts/digest.py. hard: the script passes both, and the held alerts are silently dropped by the plan as written. Source: written for this suite from the before behavior (plan SKILL.md Step 3 at 6df2738455, agents/plan-reviewer.md, context/plan-reviewer.md)."
tags: [plan, plan-reviewer-cut, plan-reviewer-cut-medium, hard]
runs: 3
max_turns: 200
timeout_seconds: 3600
allowed_tools: [Read, Glob, Grep, Skill, Bash, Edit, Write, Agent]
expected_outcome: "The final PLAN.md has a work item that routes held alerts into the morning digest, rewrites the file-naming Behavior item as a claim, and keeps paging through the outbox rather than sending mail directly; the arm's reviewer dispatch matches its contract."
---
/planning:plan Pick up the draft plan at `.work/quiet-hours/PLAN.md`. Its Brief, its phases and the design early exit (`.work/quiet-hours/design/design-resolution.md`) are written; take it from there to the approval presentation. Edit no code.
