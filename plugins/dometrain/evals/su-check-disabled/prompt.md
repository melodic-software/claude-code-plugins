---
description: "Bare /dometrain:setup runs check, its only action. An eval run has no Dometrain MCP server and no connection error for one, so per SKILL.md Task step 3 the state is disabled, with the README's Getting the MCP server as the next action; Output: 'Report exactly one state'. Boundaries and step 3: it does not run the registration command for the user, and step 1 bars inspecting settings files, environment variables or any key. Bash is granted so running the command or reading the environment is possible and its graders measure something. Needs --allow-tools Bash and a sandbox backend; no scaffold."
tags: [dometrain, setup, outcome, read-only]
max_turns: 8
timeout_seconds: 240
allowed_tools: [Read, Glob, Grep, Bash]
expected_outcome: "The reply reports the state disabled (not connected, not failed or unverified, and not a list of all three states) and points to the README's Getting the MCP server section. No Bash command runs claude mcp add or add-json, and no Read or Bash call reads a Claude Code settings or MCP config file, an .env or credentials file, the process environment, or DOMETRAIN_API_KEY."
---

/dometrain:setup
