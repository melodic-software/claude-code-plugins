---
description: 'Legacy stateless 4. "Turn off auto memory everywhere on this machine": the disable action targets user settings for machine-wide reach after confirming scope, sets both autoMemoryEnabled false and CLAUDE_CODE_DISABLE_AUTO_MEMORY, and flags that a dotfile-managed settings.json edit must be backfilled to its source. both-levers and flags-backfill read the reply. Read-only tools, so the run can describe the edit but not make it; graded on the reply. Hard because one lever alone looks sufficient.'
tags: [stateless, harness-memory, disable, hard]
max_turns: 15
timeout_seconds: 420
allowed_tools: [Read, Glob, Grep, Skill]
expected_outcome: 'The reply targets ~/.claude/settings.json for machine-wide reach once the scope is confirmed, sets autoMemoryEnabled false and CLAUDE_CODE_DISABLE_AUTO_MEMORY together, and says a settings.json tracked by a dotfile manager must be backfilled to its source rather than left drifted or reverted by the next apply.'
---

/harness-memory:stateless Turn off auto memory everywhere on this machine so Claude stops remembering. No one is around to answer questions while this runs, so tell me in your reply exactly what you would change and where it ended up.
