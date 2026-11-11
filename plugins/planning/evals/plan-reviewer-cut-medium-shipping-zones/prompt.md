---
description: "MEDIUM tier, no trigger: a five-file draft prices shipping by destination zone and builds a new country-to-zone table although shop/geo.py already maps countries to regions (context/plan-reviewer.md: build what existing code already does). Also seeded: a vague Sanity Check. hard: the duplicate needs a read of a module the draft never mentions. Source: written for this suite from the before behavior (plan SKILL.md Step 3 at 6df2738455, agents/plan-reviewer.md, context/plan-reviewer.md)."
tags: [plan, plan-reviewer-cut, plan-reviewer-cut-medium, hard]
runs: 3
max_turns: 200
timeout_seconds: 3600
allowed_tools: [Read, Glob, Grep, Skill, Bash, Edit, Write, Agent]
expected_outcome: "The final PLAN.md reuses shop.geo.country_region, gives every phase a command Sanity Check, and does not touch shop/views.py since checkout_summary already takes the country; the arm's reviewer dispatch matches its contract."
---
/planning:plan Pick up the draft plan at `.work/shipping-zones/PLAN.md`. Its Brief, its phases and the design early exit (`.work/shipping-zones/design/design-resolution.md`) are written; take it from there to the approval presentation. Edit no code.
