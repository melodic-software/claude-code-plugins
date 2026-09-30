---
description: Read worktree facts from the helper and cross-reference PRs with one gh call
tags: [worktree, source-control]
runs: 3
max_turns: 15
allowed_tools: [Read, Glob, Grep, Skill, Bash]
expected_outcome: worktree-facts.sh list runs, git worktree list --porcelain does not, and gh pr list runs exactly once
---

Show me the status of my worktrees.
