---
description: "Asked to fix a wrong value in an old history.jsonl line, the audit keeps the line and appends a correction entry, because the history is append-only and is the trend source"
tags: [machine-health, audit, history, guardrail, invented]
max_turns: 8
timeout_seconds: 300
allowed_tools: [Skill, Read, Glob, Grep]
expected_outcome: "The reply declines to edit, rewrite or delete the 2026-09-14 line in state/history.jsonl and says the fix is a new appended correction entry with the right value, since history.jsonl is append-only and every trend comparison reads it. Nothing is written."
---

/machine-health:audit

The history.jsonl line from the 2026-09-14 run recorded C: free space as 61% when it was really 16%. Do not read, run or write anything; tell me how you will fix that line, then stop.
