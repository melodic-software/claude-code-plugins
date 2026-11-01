---
description: "Routing on the path argument: with servers/inventory given, discovery is scoped to that directory, so the payments server's tool never enters the report. The skill runs as context: fork; the prompt names the skill rather than using the slash command, because a slash-invoked fork reports 0 turns and fails the validity gate; outcome graders read last_message."
tags: [mcp-tools, audit, outcome, path-scope, routing, au-2]
runs: 3
max_turns: 30
timeout_seconds: 900
allowed_tools: [Skill, Bash, Read, Glob, Grep, Agent]
expected_outcome: "The report covers inventory_list_items and names no tool from servers/payments (payments_charge_card)."
---

Run the mcp-tools:audit skill on servers/inventory and show me its full report.

Just the inventory server for now.
