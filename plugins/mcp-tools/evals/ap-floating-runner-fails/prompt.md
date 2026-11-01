---
description: "A shared config with an npx @latest server and an unversioned uvx server: P1 grades both FAIL by the checklist table, the report keeps its inventory and coverage sections, and no config file is edited. Write/Edit graders are inert unless an operator grants those tools; the shell-write grader carries the edits-nothing evidence."
tags: [mcp-tools, audit-posture, outcome, floating-version, output-contract, edits-nothing, ap-1]
runs: 3
max_turns: 20
timeout_seconds: 600
allowed_tools: [Skill, Bash, Read]
expected_outcome: "The report grades issue-tracker (@acme/issues-mcp@latest via npx) and web-fetch (mcp-server-fetch via uvx, no version) FAIL on P1 floating version, includes the inventory table with its Pin column and a coverage section with the script's not-read lines, and edits no config file."
---

/mcp-tools:audit-posture --config configs/team.mcp.json

This is the MCP config the team shares. Which of these servers could start running different code tomorrow without any of us touching it?
