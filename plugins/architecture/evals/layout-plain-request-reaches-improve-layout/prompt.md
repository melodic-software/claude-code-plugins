---
description: "A plain request with no slash command, 'do the files that change together live together', reaches /architecture:improve-layout (the skill split out of improve's former layout lens) and produces its cards from the co-change script over a scaffolded history: one four-file order cluster spread over src/orders, src/api, src/db and tests. The user steps away, so the run is unattended: it asks nothing and stops after the report. Needs --scaffold --allow-tools Bash Write and a sandbox backend."
tags: [architecture, improve-layout, co-change, routing, scaffold]
runs: 3
max_turns: 30
timeout_seconds: 900
allowed_tools: [Read, Glob, Grep, Skill, Bash, Write]
expected_outcome: "Invokes architecture:improve-layout, runs its co-change script, and reports a card for the OrderForm.tsx, orders.ts, orderRepo.ts and orders.test.ts cluster with its four folders, spread and focus taken from the script, no recorded style, a Speculative badge, and a proposed layout; it asks no question and moves no file."
---

Do the files that change together actually live together in this repo? I'm stepping away, so don't wait on questions; just give me what you find.
