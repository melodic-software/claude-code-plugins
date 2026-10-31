---
description: "Report-only contract: auditing a TypeScript tool whose _meta requiresUserInteraction is the string 'true' reports C18 FAIL and leaves the source unchanged; the file-content grader is fork-proof, while the Write/Edit graders are inert unless an operator grants those tools. The skill runs as context: fork, so tool calls inside the fork may not reach the graded trace (unverified); outcome graders read last_message."
tags: [mcp-tools, audit, outcome, edits-nothing, meta-annotations]
runs: 3
max_turns: 30
timeout_seconds: 900
allowed_tools: [Skill, Bash, Read, Glob, Grep, Agent]
expected_outcome: "tickets_grant_access gets C18 FAIL for the string \"true\"; servers/tickets/node/src/server.ts still declares it unchanged, and no file is written or edited."
---

/mcp-tools:audit servers/tickets

Shipping this tonight.
