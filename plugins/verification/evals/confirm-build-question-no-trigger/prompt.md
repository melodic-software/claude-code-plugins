---
description: 'Legacy confirm 8, no-trigger control. A quick mechanical-only question must not fire /verification:confirm (SKILL.md description: ''for quick mechanical-only checks use /toolchain:check''). no-confirm-skill grades no Skill call to verification:confirm, arm both. The routing half (naming /toolchain:check) is held: the toolchain plugin is not loaded in a run.'
tags: [verification, confirm, no-trigger, routing, no-network, routine]
max_turns: 8
timeout_seconds: 300
allowed_tools: [Read, Glob, Grep, Skill]
expected_outcome: 'No /verification:confirm call; the question is treated as a build-and-test check.'
---

does this still build and pass tests?
