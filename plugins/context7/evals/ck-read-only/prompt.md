---
description: "The check skill runs ctx7 --version, installs and downloads nothing, and reports a PASS/FAIL table"
tags: [context7, check, outcome, read-only]
max_turns: 8
timeout_seconds: 240
allowed_tools: [Bash, Read]
expected_outcome: "The run executes ctx7 --version (and npm view ctx7 version), runs no package install or npx download, and replies with a markdown table whose rows carry PASS, FAIL or INFO for the CLI, MCP and auth checks, then stops."
---

/context7:check
