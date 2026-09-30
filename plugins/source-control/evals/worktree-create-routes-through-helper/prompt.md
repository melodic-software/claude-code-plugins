---
description: Create a worktree through worktree-create.sh and enter it by path as the final action
tags: [worktree, source-control]
runs: 3
max_turns: 15
allowed_tools: [Read, Glob, Grep, Skill, Bash, Write, EnterWorktree]
expected_outcome: worktree-create.sh runs, then EnterWorktree is called with path and never with name
---

Create a worktree named feat/payment-retry so I have an isolated checkout for this feature.
