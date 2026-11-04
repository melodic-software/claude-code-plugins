---
description: With no arguments on the default branch, offer a branch or a worktree
tags: [worktree, source-control]
runs: 3
max_turns: 15
allowed_tools: [Read, Glob, Grep, Skill, Bash]
expected_outcome: The reply offers both git checkout -b and /source-control:worktree create
---

Run the source-control:worktree skill with no arguments.
