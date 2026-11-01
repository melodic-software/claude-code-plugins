---
description: "Routine. Premature gate: 'Depends on unfinished work (planned database)' and Quality Principle 6, 'Adding a database MCP before a database exists ... creates maintenance burden for zero value'. The quay repo has no database dependency, schema or connection config. Default mode is --recommend-only, so nothing is implemented. At risk in the sandbox: the skill persists verdicts under ${CLAUDE_PLUGIN_DATA} (Persist the findings), which the sandbox denied on slice A; every grader reads the report or the tool calls before that write. Needs network for the Phase 2.2 docs batch. Needs --scaffold --allow-tools Bash Write Edit WebFetch Agent."
tags: [routine, audit-automation-gaps, outcome, reject, scaffold, plugin-data-risk]
runs: 3
max_turns: 30
timeout_seconds: 1800
allowed_tools: [Skill, Read, Glob, Grep, Bash, Write, Edit, WebFetch, Agent]
expected_outcome: "The reply gives the Postgres MCP candidate a REJECT (or a CONDITIONAL whose condition is a database actually in use), citing that the repo has no database; no .mcp.json or settings file is written."
---

/harness-config:audit-automation-gaps mcp

Should we add a Postgres MCP server so Claude can query the orders database directly?
