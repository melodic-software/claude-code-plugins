---
description: "LOW tier, no trigger: a bug-fix draft caps retry backoff in one module. Seeded: it names a config constant `MAX_DELAY` that fetcher/config.py does not define (the ceiling is `MAX_BACKOFF_SECONDS`), and the bug fix names no regression test (context/plan-reviewer.md Design alignment). hard: the author believes its own constant name, and the mechanical gate checks neither. Source: written for this suite from the before behavior (plan SKILL.md Step 3 at 6df2738455, agents/plan-reviewer.md, context/plan-reviewer.md)."
tags: [plan, plan-reviewer-cut, plan-reviewer-cut-low, hard]
runs: 3
max_turns: 150
timeout_seconds: 2700
allowed_tools: [Read, Glob, Grep, Skill, Bash, Edit, Write, Agent]
expected_outcome: "The final PLAN.md uses MAX_BACKOFF_SECONDS for the ceiling and names a regression test for the uncapped delay, and adds no jitter; the arm's reviewer dispatch matches its contract."
---
/planning:plan Pick up the draft plan at `.work/backoff-cap/PLAN.md`. Its Brief, its phases and the design early exit (`.work/backoff-cap/design/design-resolution.md`) are written; take it from there to the approval presentation. Edit no code.
