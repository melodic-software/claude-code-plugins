---
description: 'Legacy audit 2. The request bundles MCP servers, hooks and subagents into the memory audit: the skill audits only the instruction and memory layer and routes the rest to harness-config''s audit and audit-automation-gaps. routes-to-harness-config reads the reply. Bash is granted for the skill''s spine. Routine: a scope boundary.'
tags: [audit, harness-memory, scope-boundary, routine]
max_turns: 20
timeout_seconds: 600
allowed_tools: [Read, Glob, Grep, Skill, Bash]
expected_outcome: 'The reply covers only CLAUDE.md, a root AGENTS.md, CLAUDE.local.md, rules and auto memory, audits no MCP server, hook, agent or skill, and points MCP servers and hooks to harness-config''s audit and agents and skills to harness-config''s audit-automation-gaps.'
---

/harness-memory:audit Run a memory health audit, and while you're at it audit my MCP servers, hooks, and subagents too. Don't change any files. No one is around to answer questions while this runs, so put what you find in your reply.
