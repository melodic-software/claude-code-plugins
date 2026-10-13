---
description: "Bare /context7:setup runs the read-only check: no install, no file write, a PASS/FAIL/INFO table, and CONTEXT7_API_KEY reported by presence only"
tags: [context7, setup, outcome, read-only]
max_turns: 8
timeout_seconds: 240
allowed_tools: [Bash, Read, Write, Edit]
expected_outcome: "The run installs and downloads nothing and makes no Write or Edit call. The reply is a markdown table with PASS, FAIL or INFO per row (CLI, MCP, auth, Windows note) and says whether CONTEXT7_API_KEY is set without any command printing its value."
---

/context7:setup
