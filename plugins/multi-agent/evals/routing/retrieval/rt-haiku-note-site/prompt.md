---
description: "Where X happens: the file and function that add the routing-rubric note when a role resolves to haiku"
tags: [routing, retrieval]
max_turns: 30
timeout_seconds: 600
allowed_tools: [Read, Glob, Grep]
expected_outcome: "Names plugins/multi-agent/scripts/resolve-roles.sh and its role_json function."
---

The current directory holds a snapshot of two plugins from a Claude Code plugin repository. Answer from its files.

When a role resolves to the haiku model, the role map gains a note pointing at the routing rubric. Which file adds that note, and which function in it? Reply with the file path from the current directory and the function name.
