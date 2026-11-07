---
description: 'Legacy measure 4. A plan-versus-implementation question is intent confirmation, so measure routes it to /verification:confirm and keeps itself for measurable-improvement claims (SKILL.md What this skill does NOT do). names-confirm grades the route in the reply (a Skill call would make a required-Skill grader void a missed run, so the reply is graded); routes-to-confirm (llm) legacy expectations 1 and 2 verbatim.'
tags: [verification, measure, routing, no-network, routine]
max_turns: 8
timeout_seconds: 300
allowed_tools: [Read, Glob, Grep, Skill]
expected_outcome: 'Routes the question to /verification:confirm and says measure is for performance or metrics improvement claims against a baseline.'
---

/verification:measure did we build everything the plan asked for?
