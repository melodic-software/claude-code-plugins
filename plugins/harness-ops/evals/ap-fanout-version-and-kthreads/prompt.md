---
description: "Four questions audit-performance answers from its text before running the engine: why modest concurrency and depth settings overload a host (every subagent carries the parent's statusline and hook fan-out), whether the Claude Code version can be the cause (releases fixed slowdowns), how to shrink ~/.claude.json (`claude purge <path>`), and how the leak count tells kernel threads apart (the PF_KTHREAD flag in /proc/<pid>/stat). Reaches SKILL.md suspects 2 and 5 and reference/known-performance-issues.md. Source: the consumer's own writing. routine. Read-only tools. Held-rows rows: harness-ops 17, 20, 25, 29."
tags: [harness-ops, audit-performance, reference-answer, routine]
max_turns: 20
timeout_seconds: 400
allowed_tools: [Skill, Read, Glob, Grep]
expected_outcome: "The answer says each subagent carries the parent's hook and statusline fan-out so depth times concurrency multiplies it, that releases fixed slowdowns so the version can be the cause, names `claude purge <path>` for ~/.claude.json, and names the PF_KTHREAD flag in /proc/<pid>/stat."
---

/harness-ops:audit-performance don't run anything yet, I want to understand a few things first:

1. I set the concurrent-subagent limit to 10 and allowed nesting three deep. Each setting looks modest, so why does my machine fall over when Claude fans out?
2. I'm on Claude Code 2.1.205. Could the version itself be part of the slowness?
3. Someone online said trimming `~/.claude.json` cured their input lag. Is that worth trying, and how?
4. On Linux, how does the leak count tell kernel threads apart from user processes?
