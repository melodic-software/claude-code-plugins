---
description: 'Legacy reads-null-fields-as-expected-state. check, then a teammate''s fresh snapshot whose used_percentage is null. setup SKILL.md lines 83-85 (fresh but null is INFO: before the first response or right after /compact; the resolver answers unknown; not a defect) and 35-37 (the reader contract owns the consumer-facing rules; reference/reader-contract.md, Capability detection (fail-open), holds the null rows). Narration: the eval home cannot hold a fresh null snapshot for the run''s own session, so the prompt asks about a teammate after the run checks this machine. Needs --allow-tools Bash Write Edit so the must-not graders can fail.'
tags: [context-usage, setup, check, read-only, narration, must-not, no-network]
max_turns: 14
timeout_seconds: 360
allowed_tools: [Read, Glob, Grep, Skill, Bash, Write, Edit]
expected_outcome: 'The null used_percentage on a fresh snapshot is INFO, the state before the first response or after /compact, with nothing to fix; the reader contract named as the rule''s owner; no install, plugin CLI write, state shell write, Write or Edit.'
---

/context-usage:setup check

Run the check on this machine first. Then a hypothetical: on a teammate's machine the live session's snapshot is fresh but its used_percentage is null. How does check grade that row, and when does that state happen? What should they do about it, and which document owns the rule behind that grade?
