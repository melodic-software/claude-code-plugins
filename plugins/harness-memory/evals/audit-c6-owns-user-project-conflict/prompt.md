---
description: 'Legacy audit 11. The user CLAUDE.md forbids AskUserQuestion and the project CLAUDE.md requires it before destructive actions; asked whether that is C6 or audit-instructions'' I15, the skill answers C6, because both files are in the discover-instruction-surfaces population, while nested CLAUDE.md, auto memory and non-memory surfaces stay with I15. c6-owns-it reads the reply. Bash is granted for the skill''s spine. Hard because I15 is the precedence check and the pair looks like a precedence question.'
tags: [audit, harness-memory, ownership, hard]
max_turns: 20
timeout_seconds: 600
allowed_tools: [Read, Glob, Grep, Skill, Bash]
expected_outcome: 'The reply attributes the user-versus-project contradiction to C6 Consistency, not I15, because both files are in the discover-instruction-surfaces population compared across scopes, and says nested CLAUDE.md, auto memory and non-memory surfaces stay outside C6 with I15.'
---

/harness-memory:audit My ~/.claude/CLAUDE.md says never use AskUserQuestion, and this project's CLAUDE.md says always use AskUserQuestion before any destructive action. Is that your C6 check or audit-instructions' I15? Don't change any files. No one is around to answer questions while this runs, so put the answer in your reply.
