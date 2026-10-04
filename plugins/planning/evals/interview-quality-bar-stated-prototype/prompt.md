---
description: "Control. The prompt states the bar (a throwaway prototype), so round 1 must not ask it again and its depth should match a prototype. Row 38 of the Pocock sync."
tags: [interview, quality-bar, row38]
runs: 3
max_turns: 12
timeout_seconds: 600
allowed_tools: [Read, Glob, Grep, Skill]
expected_outcome: "Round 1 asks scoping questions, does not ask the quality bar again, and keeps production concerns (auth, scaling, monitoring, CI) out of the round or explicitly deferred"
---

/planning:interview I want a quick throwaway prototype of a habit-tracker web app to show a friend this weekend. It will never ship and nobody else will use it.
