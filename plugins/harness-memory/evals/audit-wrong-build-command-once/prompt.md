---
description: 'Legacy audit 8. CLAUDE.md names pnpm and vitest without invocations and says to build with `pnpm run compile`, which package.json does not define; the real commands sit in auto memory. C9 FAILs the compile line once (not again under C7), does not WARN that commands are missing because step 0 finds them in auto memory, and notes the bare tool names. c9-flags-compile reads the reply. Bash is granted for the skill''s spine. Hard because three checks (C3, C7, C9) could each claim the same lines.'
tags: [audit, harness-memory, commands, hard]
max_turns: 25
timeout_seconds: 900
allowed_tools: [Read, Glob, Grep, Skill, Bash]
expected_outcome: 'The reply FAILs `pnpm run compile` under C9 because package.json has no compile script, reports it once and not under C7, does not WARN that build and test commands are missing since auto memory states them (a C3 placement question), and flags "we use pnpm and vitest" as tool names without invocations.'
---

/harness-memory:audit Audit my memory health. My root CLAUDE.md says "we use pnpm and vitest" but doesn't spell out the invocations. It also says to build with `pnpm run compile`, though package.json only defines `build`, `test`, and `lint`. Separately, our actual build and test commands are already recorded in auto memory from when you worked them out; take that as given and don't go looking in the memory directory. Leave user-level config out of this and don't change any files. No one is around to answer questions while this runs, so put what you find in your reply.
