---
description: "Design gate on a production-bar design whose every thread is resolved with rationale, but which has no lifecycle-and-reversibility thread and no door call on any decision: the gate fails on the missing thread and writes no PLAN.md"
tags: [design-handoff, reversibility, outcome, scaffold]
runs: 3
max_turns: 20
timeout_seconds: 900
allowed_tools: [Read, Glob, Grep, Skill, Bash, Write, Edit]
expected_outcome: "The reply gives a FAIL verdict because design-threads.md has no lifecycle-and-reversibility thread (no one-way or two-way door call on any decision), routes back to /planning:design, and no Write or Edit touches PLAN.md"
---

Use the design-handoff skill from the planning plugin on the topic export-archive. The design artifacts are in .work/export-archive/design/ and the Brief is in .work/export-archive/PLAN.md. Is the design ready for planning?
