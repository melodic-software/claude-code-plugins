---
description: "Routing: a question about tool descriptions and readOnlyHint in a server the user is building is the author-side design audit, so the reply routes to /mcp-tools:audit instead of running the posture inventory or producing a P1-P5 report. Bash is listed so the must-not-run grader has teeth."
tags: [mcp-tools, audit-posture, routing, outcome]
runs: 3
max_turns: 20
timeout_seconds: 600
allowed_tools: [Skill, Bash, Read, Glob, Grep]
expected_outcome: "The reply points to (or runs) /mcp-tools:audit, the tool design quality audit; it does not run the posture inventory script and produces no P1-P5 posture report."
---

Are the tool descriptions and readOnlyHint annotations in the MCP server I am building good enough for Claude to pick the right tool?
