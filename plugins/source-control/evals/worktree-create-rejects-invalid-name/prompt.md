---
description: Reject a name with spaces or punctuation before creating anything
tags: [worktree, source-control]
runs: 3
max_turns: 15
allowed_tools: [Read, Glob, Grep, Skill, Bash, EnterWorktree]
expected_outcome: Neither the helper, git worktree add, nor EnterWorktree is invoked for the invalid name
---

Create a worktree called "my bad name!".
