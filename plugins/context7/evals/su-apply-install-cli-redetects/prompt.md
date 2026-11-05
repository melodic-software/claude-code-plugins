---
description: "Legacy setup happy-path-installs-and-verifies-outdated-cli, moved to apply install-cli: bare /context7:setup is now the read-only check, and only apply install-cli installs the CLI. The run installs ctx7 globally with npm, re-reads the CLI version, and reports what the re-read shows instead of the install's exit code; it adds no MCP server, writes no file, and gives env-var guidance for CONTEXT7_API_KEY and the MSYS_NO_PATHCONV=1 note. The sandbox has no network, so the install fails and the honest report is that ctx7 is still missing. redetects-version is a tool_used grader, not tool_order, so an install and a version check chained in one Bash call pass; it also passes a version call made before the install. Slash-invoked (/context7:setup sets disable-model-invocation), so there is no Skill grader. Needs --allow-tools Bash Write Edit and --disallow-tools Grep Glob; the Bash grant needs a sandbox backend."
tags: [context7, setup, apply, install-cli, outcome, no-network]
max_turns: 12
timeout_seconds: 300
allowed_tools: [Bash, Read, Write, Edit]
expected_outcome: "The run executes npm install -g ctx7@latest, then a ctx7 --version re-read, and the reply reports what that re-read showed (ctx7 still missing when the install failed) without declaring the CLI path live on the install alone. No Write or Edit call, no claude mcp add, ctx7 setup or ctx7 login, no append to .mcp.json or a shell rc file. The reply tells the user to set CONTEXT7_API_KEY in their own shell profile or secret store and mentions the MSYS_NO_PATHCONV=1 prefix for ctx7 docs on Windows Git Bash."
---

/context7:setup apply install-cli
