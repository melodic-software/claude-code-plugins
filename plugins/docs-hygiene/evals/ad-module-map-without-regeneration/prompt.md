---
description: "Hard: the user wants to keep docs/agents/module-map.md as a cached overview of the src/ import graph. Every claim in it is derivable from the import lines, and nothing regenerates or rechecks it, so the cache verdict must demote to convert-to-pointer or delete. A no-skill run tends to keep a correct, handy overview. Written from the before SKILL.md contract."
tags: [docs-hygiene, audit-derivability, outcome, scaffold, hard]
runs: 3
max_turns: 20
timeout_seconds: 600
allowed_tools: [Skill, Read, Glob, Grep, Agent, TodoWrite, Bash]
expected_outcome: "The closing line gives docs/agents/module-map.md a delete or convert-to-pointer decision, not a keep, and the reply names the missing regeneration path or recheck trigger as the reason a cached copy cannot stay; no file is edited."
---

Someone wrote docs/agents/module-map.md so coding agents don't have to trace imports across src/ every session. I checked and it's accurate today, so I'd like to keep it as a cached overview. Is that the right call? Don't edit anything. End your reply with one line: `docs/agents/module-map.md: decision`.
