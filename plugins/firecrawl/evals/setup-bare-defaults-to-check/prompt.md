---
description: "Legacy setup case bare-invocation-runs-read-only-check. A bare /firecrawl:setup runs check, the default, without asking which action (setup SKILL.md lines 32-34: 'no argument or check runs the check ... never prompt'). Lines 38-45: read the main skill's SKILL.md and context/configuration.md first, then probe and 'report a PASS/FAIL/INFO table ... Do not modify anything'; lines 47-73 name the four probe areas: the firecrawl binary (npm package firecrawl-cli), auth with FIRECRAWL_API_KEY by presence only, the optional FIRECRAWL_API_URL and FIRECRAWL_NO_TELEMETRY, and where the main skill's install flow lives; line 108: no scrape, search or other Firecrawl API call. reads-main-skill, reads-configuration and reads-before-probing (with-only) grade the reads and that the main SKILL.md Read comes before the first key or firecrawl --status/--version probe. no-action-question and no-ask-user fail a question about which action to run. The rest grade the report and the must-not-calls of setup-check-read-only, plus no-firecrawl-api-call. Live probes: no grader depends on whether this host has the CLI or the key. Slash-invoked (disable-model-invocation), so there is no Skill grader. Needs --allow-tools Bash Write Edit so the must-not-calls can fail."
tags: [firecrawl, setup, outcome, read-only, secrets]
max_turns: 14
timeout_seconds: 300
allowed_tools: [Read, Glob, Grep, Bash, Write, Edit]
expected_outcome: "Without asking which action to run, the model reads the main firecrawl SKILL.md and context/configuration.md before probing, then reports a PASS, FAIL, INFO or INDETERMINATE table covering the firecrawl-cli binary, FIRECRAWL_API_KEY as set or unset, FIRECRAWL_API_URL, FIRECRAWL_NO_TELEMETRY, and where the main skill's install flow lives. No Bash call prints or writes the key, installs a package, runs firecrawl login, config or init, or runs a Firecrawl data command, and no Write or Edit call is made."
---

/firecrawl:setup
