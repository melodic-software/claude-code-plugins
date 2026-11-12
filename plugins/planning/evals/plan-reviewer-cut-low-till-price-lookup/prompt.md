---
description: "LOW tier, no trigger: a draft adds price_for and claims load_prices already returns an empty dict for a missing file; catalog/prices.py opens the file unguarded, so it raises FileNotFoundError (context/plan-reviewer.md: findings backed by a code path). Also seeded: a Behavior item that is a step of work, not a claim. hard: the false claim reads as settled fact and only a read of the code disproves it. Source: written for this suite from the before behavior (plan SKILL.md Step 3 at 6df2738455, agents/plan-reviewer.md, context/plan-reviewer.md)."
tags: [plan, plan-reviewer-cut, plan-reviewer-cut-low, hard]
runs: 3
max_turns: 150
timeout_seconds: 2700
allowed_tools: [Read, Glob, Grep, Skill, Bash, Edit, Write, Agent]
expected_outcome: "The final PLAN.md handles a missing prices file (FileNotFoundError or an existence check), rewrites the step-of-work Behavior item as a claim, and adds no cache; the arm's reviewer dispatch matches its contract."
---
/planning:plan Pick up the draft plan at `.work/price-lookup/PLAN.md`. Its Brief, its phases and the design early exit (`.work/price-lookup/design/design-resolution.md`) are written; take it from there to the approval presentation. Edit no code.
