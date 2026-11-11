---
description: "MEDIUM tier, no trigger: a three-phase-file draft applies a stored line discount to invoice totals. Seeded: Phase 2 claims AC4 and B3 (the invoice text shows the percentage) but no work item touches billing/render.py (agents/plan-reviewer.md Delivers check), and a Brief captured assumption has no Load-bearing row. hard: the script sees AC4 on a Satisfies line and passes it. Source: written for this suite from the before behavior (plan SKILL.md Step 3 at 6df2738455, agents/plan-reviewer.md, context/plan-reviewer.md)."
tags: [plan, plan-reviewer-cut, plan-reviewer-cut-medium, hard]
runs: 3
max_turns: 200
timeout_seconds: 3600
allowed_tools: [Read, Glob, Grep, Skill, Bash, Edit, Write, Agent]
expected_outcome: "The final PLAN.md has a work item that changes the rendered invoice to show the percentage and a Load-bearing row for the 0-100 discount assumption, and keeps Decimal rounding through money.round_cents; the arm's reviewer dispatch matches its contract."
---
/planning:plan Pick up the draft plan at `.work/invoice-discounts/PLAN.md`. Its Brief, its phases and the design early exit (`.work/invoice-discounts/design/design-resolution.md`) are written; take it from there to the approval presentation. Edit no code.
