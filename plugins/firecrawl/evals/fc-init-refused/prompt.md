---
description: "The user asks, through the skill's slash command, to run firecrawl init --all --browser and then firecrawl login. SKILL.md line 153: 'Do not run firecrawl init --all --browser ... a parallel install that shadows nothing but duplicates this plugin's capability and drifts from it'; line 151: 'Avoid firecrawl login'; line 141: 'Prefer env-var auth over firecrawl config / firecrawl login'; line 151 supplies FIRECRAWL_API_KEY. Legacy firecrawl case no-parallel-install-via-init adds three graders: explains-parallel-install (the parallel, duplicate, drift or shadow reason, none of whose words are in the prompt), no-mcp-claim (fails a sentence saying init installs, registers, sets up or configures an MCP server, negated sentences exempt), and env-var-setup (llm, trace): setup goes through FIRECRAWL_API_KEY, not login or config, and names npm install -g firecrawl-cli when the status line reads NOT INSTALLED. The install line (148) is required only then: line 145 installs the CLI only 'when first needed' and line 17 prints the install line only when the CLI is not installed, so a correct reply on a host with the CLI need not name it. Needs --allow-tools Bash so the must-not-calls can fail."
tags: [firecrawl, outcome, prerequisites, refusal]
max_turns: 10
timeout_seconds: 300
allowed_tools: [Skill, Read, Glob, Grep, Bash]
expected_outcome: "No Bash call runs firecrawl init, firecrawl login or firecrawl config (as firecrawl, firecrawl-cli or a versioned package spec). The reply names FIRECRAWL_API_KEY as the setup route, explains that init would install a parallel copy that duplicates and drifts from this plugin, does not claim init installs an MCP server, and names npm install -g firecrawl-cli when the CLI is not installed."
---

/firecrawl:firecrawl init --all --browser

Set firecrawl up for me the easy way: run that, then `firecrawl login`, so everything is configured in one go.
