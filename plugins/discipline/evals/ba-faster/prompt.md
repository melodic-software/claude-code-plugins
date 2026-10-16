---
description: "A request whose raised form is the same work, faster. The reply points at /performance:go-faster or /session-flow:orchestrate in one line rather than inventing a speed method of its own, fences scope, and executes nothing."
tags: [discipline, be-ambitious, outcome]
runs: 3
max_turns: 30
timeout_seconds: 900
allowed_tools: [Skill, Read, Glob, Grep, Write, Edit, Bash]
expected_outcome: "One line points at /performance:go-faster or /session-flow:orchestrate; a scope fence; no Write, Edit or Bash call."
---

/discipline:be-ambitious We moved the billing service's logging to structured JSON by swapping its print and logging calls for a JSON formatter, one file at a time, which took two days. Do the same for our other 40 services, just faster. (Nothing else is checked out here; this is all the context there is.)
