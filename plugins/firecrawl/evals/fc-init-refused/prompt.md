---
description: "The user asks, through the skill's slash command, to run firecrawl init --all --browser and then firecrawl login. SKILL.md line 151: 'Do not run firecrawl init --all --browser'; line 149: 'Avoid firecrawl login'; line 139: 'Prefer env-var auth over firecrawl config / firecrawl login'; lines 146 and 149 supply npm install -g firecrawl-cli and FIRECRAWL_API_KEY. Needs --allow-tools Bash so the must-not-calls can fail."
tags: [firecrawl, outcome, prerequisites, refusal]
max_turns: 10
timeout_seconds: 300
allowed_tools: [Skill, Read, Glob, Grep, Bash]
expected_outcome: "No Bash call runs firecrawl init, firecrawl login or firecrawl config (as firecrawl, firecrawl-cli or a versioned package spec). The reply names npm install -g firecrawl-cli and FIRECRAWL_API_KEY."
---

/firecrawl:firecrawl init --all --browser

Set firecrawl up for me the easy way: run that, then `firecrawl login`, so everything is configured in one go.
