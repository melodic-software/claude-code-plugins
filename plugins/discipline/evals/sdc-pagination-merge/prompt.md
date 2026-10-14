---
description: "A function marked done is 0-based where the requirement is 1-based and skips the size check. The run must stop, send the artifact and requirement to one fresh non-fork subagent, surface the off-by-one and the out-of-focus size check, and work the fix with the user"
tags: [discipline, scrutinize-dont-coast, outcome, scaffold]
max_turns: 15
timeout_seconds: 400
allowed_tools: [Skill, Read, Glob, Grep, Agent]
expected_outcome: "One to three Agent calls, none with subagent_type fork; the reply names the 1-based off-by-one and the missing size check (ValueError), and hands the fix back to the user as a question or a call for their decision."
---

/discipline:scrutinize-dont-coast I'm about to merge src/pagination.py; focus on the paging math
