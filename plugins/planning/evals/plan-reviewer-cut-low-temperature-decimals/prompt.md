---
description: "LOW tier, no trigger: a draft adds a decimals option to a temperature formatter. Seeded: a work item adds a unit switch the Brief's Out-of-scope excludes (context/plan-reviewer.md Plan mechanics), and the phase's Sanity Check is a vague `looks right` the script counts as present. routine for the out-of-scope seed, which Step 4.7's reading check also covers; hard for the vague Sanity Check. Source: written for this suite from the before behavior (plan SKILL.md Step 3 at 6df2738455, agents/plan-reviewer.md, context/plan-reviewer.md)."
tags: [plan, plan-reviewer-cut, plan-reviewer-cut-low, hard]
runs: 3
max_turns: 150
timeout_seconds: 2700
allowed_tools: [Read, Glob, Grep, Skill, Bash, Edit, Write, Agent]
expected_outcome: "The final PLAN.md drops the unit switch, replaces the vague Sanity Check with a command, and does not switch to Decimal; the arm's reviewer dispatch matches its contract."
---
/planning:plan Pick up the draft plan at `.work/temp-decimals/PLAN.md`. Its Brief, its phases and the design early exit (`.work/temp-decimals/design/design-resolution.md`) are written; take it from there to the approval presentation. Edit no code.
