---
description: "Contract case for the PRD hand-off when the PRD is locked, the engineering scope is clear and the externals are understood. Why hard: the reflex is to send the user back through an interview or exploration that has nothing left to ask."
tags: [prd, handoff]
runs: 3
max_turns: 12
timeout_seconds: 600
allowed_tools: [Read, Glob, Grep, Skill]
expected_outcome: "The plan comes next, directly or through the design step's one-line early exit, since product intent is locked and engineering scope and externals are already understood, with no further interview, exploration or research detour"
---

/planning:prd We just finished and locked the PRD for letting members export their listening history as a CSV file. The engineering scope is already clear: it reuses the existing export job queue, there are no untouchable areas, and the performance budget is agreed. We also understand the one library involved. Hand off: what should I run next?
