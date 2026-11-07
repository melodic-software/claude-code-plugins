---
description: 'Legacy audit 1. A small repository with a short CLAUDE.md and two rules gets the default audit: per-check PASS/FAIL/WARN results over CLAUDE.md, rules and auto memory, with judgment-tier findings labeled judgment candidate apart from the deterministic spine. c1-severity and judgment-candidate read the reply. Bash is granted for the skill''s spine and per-check scripts. Routine: the default action on a healthy layer.'
tags: [audit, harness-memory, routine]
max_turns: 25
timeout_seconds: 900
allowed_tools: [Read, Glob, Grep, Skill, Bash]
expected_outcome: 'The reply audits CLAUDE.md, the two rules and auto memory against the codified checklist, gives each check a PASS, FAIL or WARN, and labels the judgment-tier findings judgment candidate, distinct from the deterministic-spine checks.'
---

/harness-memory:audit Audit my memory health: is my CLAUDE.md and rules layer in good shape? Leave user-level config out of this and don't change any files. No one is around to answer questions while this runs, so put what you find in your reply.
