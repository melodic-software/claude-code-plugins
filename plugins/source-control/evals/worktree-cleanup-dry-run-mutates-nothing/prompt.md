---
description: A dry-run cleanup reports candidates and removes nothing
tags: [worktree, source-control]
runs: 3
max_turns: 15
allowed_tools: [Read, Glob, Grep, Skill, Bash]
expected_outcome: worktree-facts.sh list runs and no removal, branch deletion, or non-dry prune command runs
---

Run a worktree cleanup dry run.
