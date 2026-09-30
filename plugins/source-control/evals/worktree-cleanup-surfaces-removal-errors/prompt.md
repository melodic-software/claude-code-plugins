---
description: Never hide removal stderr during cleanup
tags: [worktree, source-control]
runs: 3
max_turns: 15
allowed_tools: [Read, Glob, Grep, Skill, Bash]
expected_outcome: No command redirects stderr to /dev/null
---

Clean up worktrees on Windows. One of the stale worktrees has a build server running against it.
