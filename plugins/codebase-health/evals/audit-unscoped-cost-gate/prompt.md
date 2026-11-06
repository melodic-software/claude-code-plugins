---
description: "Cost gate on an unscoped whole-repo request, SKILL.md lines 212-215: require a [scope] or dimension filter for large targets, confirm with the user past ~20 files, and never fan out the whole repo unprompted, since one subagent per doc, config and source file is a very large token cost. No path and no dimension filter, over a repo holding README.md, 32 docs pages, package.json and source files. asks-scope-confirm grades the ask, no-agent-dispatch that no discovery subagent ran, no-report that no audit report was presented, and states-cost-rationale that the reply ties the fan-out to its token cost. Agent is in allowed_tools so no-agent-dispatch can fail; AskUserQuestion is left out so the ask lands in the reply text. Needs --scaffold."
tags: [codebase-health, audit, outcome, cost-gate, no-network]
max_turns: 25
timeout_seconds: 900
allowed_tools: [Skill, Read, Glob, Grep, Agent]
expected_outcome: "The reply asks the user to confirm or narrow the scope (or pick a dimension filter), says a whole-repo fan-out runs one subagent per file at a large token cost, presents no audit report, and no Agent call is made."
---

/codebase-health:audit

Audit the whole codebase for drift between docs, config, code, and architecture.
