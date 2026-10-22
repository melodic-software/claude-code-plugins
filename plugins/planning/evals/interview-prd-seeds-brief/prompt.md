---
description: "Unattended lock with a locked PRD.md in the topic's memory slice: the Brief's ### Problem carries the PRD's Problem (pickers walking back to the desk for a pick-list reprint), and the PRD's one assumption (handheld scanners have a browser) sits under ### Captured assumptions tagged (from PRD), never as a constraint-ledger row, and the Goal's Vision line carries the PRD's Vision (every floor task on the device in the picker's hand). Needs --allow-tools Write."
tags: [interview, brief, prd, assumptions, problem, scaffold]
runs: 3
max_turns: 30
timeout_seconds: 900
allowed_tools: [Read, Glob, Grep, Skill, Bash, Write, Edit]
expected_outcome: ".work/pick-list-reprint/PLAN.md has a ### Problem about pickers walking back to the dispatch desk to reprint a lost pick list, and under ### Captured assumptions a line with the handheld-scanner browser assumption tagged (from PRD), and under ### Goal a '- Vision (where this heads):' line about every floor task arriving on the picker's device; .work/pick-list-reprint/interview-checklist.md has no C<N> constraint row for that assumption"
---

/planning:interview lock

This run is unattended: nobody will answer questions, so record anything only I can decide as blocked and keep going.

Lock the Brief. Use the topic slug `pick-list-reprint`. I wrote the PRD for this already; it is in the topic's memory slice.

Goal: a picker opens the current pick list for an order on the floor instead of asking the dispatch desk for a reprint. This is an internal tool.

Acceptance: opening an order's pick list shows every line's bin, SKU and quantity in the same order as the printed list; an order id that does not exist shows a not-found message.
