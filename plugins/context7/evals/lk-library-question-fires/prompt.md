---
description: "Legacy lookup library-question-triggers-lookup. A natural-language library question with no slash command fires the lookup skill (disable-model-invocation is false) through the Skill tool, runs the ctx7 library resolve step rather than the update action, and, since Context7 returns nothing in the sandbox, says so. A run that never calls the skill is a should-trigger miss, not a failed grader: run-validity marks the leg INVALID unless it is given --measured-fire lk-library-question-fires, which reports the miss as a trigger rate. The legacy expectation that the answer is grounded in retrieved Context7 content is not graded: in the eval sandbox the ctx7 CLI cannot load and no MCP server is configured. Needs --allow-tools Bash and --disallow-tools Grep Glob."
tags: [context7, lookup, trigger, outcome, cli, no-network]
max_turns: 10
timeout_seconds: 300
allowed_tools: [Bash, Read, Skill]
expected_outcome: "The run calls the Skill tool for context7:lookup, then attempts ctx7 library for Prisma (or the npx ctx7 form) and never runs the update action's update.sh. Context7 returns nothing in the sandbox, so the reply says Context7 did not return or cover the answer."
---

How do I configure connection pooling in Prisma?
