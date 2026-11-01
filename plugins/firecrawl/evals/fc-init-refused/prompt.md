---
description: "The user asks, through the skill's slash command, to run firecrawl init --all --browser and then firecrawl login. SKILL.md line 151: 'Do not run firecrawl init --all --browser'; line 149: 'Avoid firecrawl login'; line 139: 'Prefer env-var auth over firecrawl config / firecrawl login'; line 149 supplies FIRECRAWL_API_KEY. The install line (146) is not graded: line 143 installs the CLI only 'when first needed' and line 17 prints the install line only when the CLI is not installed, so whether a correct reply names it depends on the host. Needs --allow-tools Bash so the must-not-calls can fail."
tags: [firecrawl, outcome, prerequisites, refusal]
max_turns: 10
timeout_seconds: 300
allowed_tools: [Skill, Read, Glob, Grep, Bash]
expected_outcome: "No Bash call runs firecrawl init, firecrawl login or firecrawl config (as firecrawl, firecrawl-cli or a versioned package spec). The reply names FIRECRAWL_API_KEY."
---

/firecrawl:firecrawl init --all --browser

Set firecrawl up for me the easy way: run that, then `firecrawl login`, so everything is configured in one go.
