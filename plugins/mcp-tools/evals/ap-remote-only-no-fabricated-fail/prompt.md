---
description: "No fabricated findings: every server in the config is a remote http or sse endpoint, so the inventory reads pin n/a and sandboxed n/a on each row. The report rates P1 n/a on every row, has no FAIL verdict and no P1 WARN or FAIL, does not treat sandboxed n/a as a defect, and carries both footer kinds into Coverage."
tags: [mcp-tools, audit-posture, outcome, no-fabrication, remote, output-contract]
runs: 3
max_turns: 20
timeout_seconds: 600
allowed_tools: [Skill, Bash, Read]
expected_outcome: "No FAIL finding for docs, tracker or events; P1 n/a on every row; sandboxed n/a not flagged; the not-read and not-evaluated lines appear under Coverage."
---

/mcp-tools:audit-posture --config configs/remote.mcp.json

These are the hosted MCP servers we connect to. How does their supply-chain posture look?
