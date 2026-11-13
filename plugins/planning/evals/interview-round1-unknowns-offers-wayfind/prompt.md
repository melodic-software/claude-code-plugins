---
description: "The opening request itself names unknowns in four separate areas. Why hard: no round has run yet, so the fog trigger cannot fire; the easy failures are to say nothing about wayfind until later rounds, or to treat the fog as a reason to switch to wayfind and skip the interview."
tags: [interview, routing, wayfind, round-1]
runs: 3
max_turns: 12
timeout_seconds: 600
allowed_tools: [Read, Glob, Grep, Skill]
expected_outcome: "Round 1 includes a question recommending /planning:wayfind chart for the four unknown areas, worded so the user can accept or decline it, and the other round-1 questions go out in the same message; wayfind is not invoked"
---

/planning:interview I want to move our clinic booking app from a single clinic to a group of clinics. Honestly I don't know yet how patient records should be shared between clinics, how billing would split across them, whether staff sign in once or per clinic, or how to migrate the existing appointments. I'm here and will answer your questions.

[Session state: an engineering session in this repository. Nothing has been asked yet. The context-usage zone is healthy. Write your first message to the user.]
