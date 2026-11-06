---
description: "Both the export_ledger description and the server instructions run past the 2,048-character floor: each is C4 WARN, never FAIL, presented as this skill's own rule (OPINION authority, built on client behavior), not a spec rule. An llm judge checks the reply advises keeping critical details near the start of both texts. The skill runs as context: fork; the prompt names the skill rather than using the slash command, because a slash-invoked fork reports 0 turns and fails the validity gate; outcome graders read last_message."
tags: [mcp-tools, audit, outcome, description-length, server-instructions, severity, no-network]
runs: 3
max_turns: 30
timeout_seconds: 900
allowed_tools: [Skill, Bash, Read, Glob, Grep, Agent]
expected_outcome: "export_ledger gets C4 WARN (not FAIL) for its over-long description and the server-level row gets C4 WARN for its over-long instructions; both come with advice to keep critical details near the start; the floor is presented as the skill's own rule, not a spec violation."
---

Run the mcp-tools:audit skill on servers/ledger and show me its full report.

Include the server-level result, and tell me what to fix first.
