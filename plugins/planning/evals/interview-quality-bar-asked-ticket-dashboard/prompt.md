---
description: "Hard case. Why hard: a second vague build request, in a different domain, with no stated quality bar; the round can fill with scope and data-source questions and never ask how robust the result must be. Row 38 of the Pocock sync."
tags: [interview, quality-bar, row38]
runs: 3
max_turns: 12
timeout_seconds: 600
allowed_tools: [Read, Glob, Grep, Skill]
expected_outcome: "Round 1 asks which quality bar the work is for (a prototype or throwaway, an internal tool, or production) before deeper scoping questions"
---

/planning:interview Let's build a dashboard that shows how many support tickets we close each week and how long they stay open.
