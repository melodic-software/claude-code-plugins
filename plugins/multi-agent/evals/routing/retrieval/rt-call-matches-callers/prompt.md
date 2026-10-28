---
description: "Trace callers: the direct callers of the eval validator's call_matches helper"
tags: [routing, retrieval]
max_turns: 30
timeout_seconds: 600
allowed_tools: [Read, Glob, Grep]
expected_outcome: "Names grade_tool_used and grade_tool_order, and no indirect caller."
---

The current directory holds a snapshot of two plugins from a Claude Code plugin repository. Answer from its files.

Which functions call `call_matches` directly? For each call, name the top-level function it sits in. Reply with only the function names, one per line.
