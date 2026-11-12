---
description: "MEDIUM tier, no trigger: a five-file draft adds author search. Seeded: the Brief records an appetite and the plan has no Appetite fit line, and the plan says search_title already sorts by title, so AC3 needs no work, while library/search.py returns matches in catalogue order. hard: the sorting claim is false only on reading the code, and no script criterion covers either seed. Source: written for this suite from the before behavior (plan SKILL.md Step 3 at 6df2738455, agents/plan-reviewer.md, context/plan-reviewer.md)."
tags: [plan, plan-reviewer-cut, plan-reviewer-cut-medium, hard]
runs: 3
max_turns: 200
timeout_seconds: 3600
allowed_tools: [Read, Glob, Grep, Skill, Bash, Edit, Write, Agent]
expected_outcome: "The final PLAN.md has an Appetite fit line and a work item that sorts author results by title, and adds no search dependency; the arm's reviewer dispatch matches its contract."
---
/planning:plan Pick up the draft plan at `.work/author-search/PLAN.md`. Its Brief, its phases and the design early exit (`.work/author-search/design/design-resolution.md`) are written; take it from there to the approval presentation. Edit no code.
