---
description: 'Legacy stateless 1. A plain question about saved memories and whether auto memory is on runs the default status action: the effective state across settings scopes and the env var, where the store lives and whether it holds files, changing nothing. reports-state reads the reply. Read-only tools, graded on the reply. Routine: the default action.'
tags: [stateless, harness-memory, status, routine]
max_turns: 15
timeout_seconds: 420
allowed_tools: [Read, Glob, Grep, Skill]
expected_outcome: 'The reply gives the effective auto-memory state from autoMemoryEnabled and CLAUDE_CODE_DISABLE_AUTO_MEMORY across settings scopes, names where the store lives (default or autoMemoryDirectory override) and whether MEMORY.md or topic files exist, and changes nothing.'
---

/harness-memory:stateless Does Claude have any saved memories about this repo, and is auto memory on? No one is around to answer questions while this runs, so put the answer in your reply.
