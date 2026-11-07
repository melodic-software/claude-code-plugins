---
description: "Legacy scrutinize-dont-coast 2, its prompt behind the slash command. The scaffold seeds a one-line migration that meets its requirement (nullable column, no default, index or backfill, a down migration that drops it) and says it was checked. A clean pass is a real outcome and is said plainly (SKILL.md lines 39-40 and 133-134). fresh-context-pass and pass-is-not-a-fork grade the pass (SKILL.md lines 64-73), reports-clean a clean verdict word that is not negated, clean-stated-plainly (llm) the three legacy expectations verbatim. Needs --scaffold."
tags: [discipline, scrutinize-dont-coast, outcome, scaffold, no-network]
max_turns: 15
timeout_seconds: 400
allowed_tools: [Skill, Read, Glob, Grep, Agent]
expected_outcome: "One to three non-fork Agent calls; the reply reports the migration clean, with no invented fault and no vague caveat."
---

/discipline:scrutinize-dont-coast second-guess the migration script you just produced. (It was already checked against the schema and the rollback path, and both were confirmed.)
