---
description: "Routing on the path argument: with servers/inventory given, discovery is scoped to that directory, so the payments server's tool never enters the report. The skill runs as context: fork, so tool calls inside the fork may not reach the graded trace (unverified); outcome graders read last_message."
tags: [mcp-tools, audit, outcome, path-scope, routing]
runs: 3
max_turns: 30
timeout_seconds: 900
allowed_tools: [Skill, Bash, Read, Glob, Grep, Agent]
expected_outcome: "The report covers inventory_list_items and names no tool from servers/payments (payments_charge_card)."
---

/mcp-tools:audit servers/inventory

Just the inventory server for now.
