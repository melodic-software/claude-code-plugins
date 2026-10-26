---
description: "Trace callers: every script that runs the multi-agent role resolver, its test file aside"
tags: [routing, retrieval]
max_turns: 30
timeout_seconds: 600
allowed_tools: [Read, Glob, Grep]
expected_outcome: "Lists the route, setup and audit-defaults list-pointers scripts, and no other script."
---

The current directory holds a snapshot of two plugins from a Claude Code plugin repository. Answer from its files.

List every script that runs `plugins/multi-agent/scripts/resolve-roles.sh`, leaving out its own test file. Reply with only the paths from the current directory, one per line.
