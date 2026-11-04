---
description: Gather repository context first, with the inventory bounded in the command
tags: [worktree, source-control]
runs: 3
max_turns: 15
allowed_tools: [Read, Glob, Grep, Skill, Bash]
expected_outcome: The inventory runs as git worktree list piped to head, and git rev-parse --git-common-dir runs
---

With the source-control:worktree skill, tell me how many worktrees this repository has.
