---
description: Read worktree facts from the helper and look up PRs per branch, never with a repo-wide list
tags: [worktree, source-control]
runs: 3
max_turns: 15
allowed_tools: [Read, Glob, Grep, Skill, Bash]
expected_outcome: worktree-facts.sh list runs, git worktree list --porcelain does not, and every gh pr list is scoped to one branch with --head
---

Show me the status of my worktrees.
