---
description: "No correct test seam: record the absence as an architectural finding, never a shallow false-confidence test"
tags: [debug, converted]
runs: 3
max_turns: 15
timeout_seconds: 600
allowed_tools: [Read, Glob, Grep, Skill]
expected_outcome: "Declines to put a regression test in the shallow seam and records the missing correct seam as a Phase 6 architectural finding"
---

/debugging:debug I found and fixed the bug, but the only place a regression test would fit is a shallow unit test that can't replicate the multi-caller chain that actually triggered it.
