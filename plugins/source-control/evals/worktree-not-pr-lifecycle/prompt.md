---
description: Stay out of push, PR, and commit work
tags: [worktree, source-control]
runs: 3
max_turns: 15
allowed_tools: [Read, Glob, Grep, Skill, Bash]
expected_outcome: No git push, gh pr create/merge/close, git add, or git commit
---

This branch is done. Use the worktree skill to push it and open and merge the PR for me.
