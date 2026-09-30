---
description: Stash tracked and untracked edits before reusing a worktree after a merge
tags: [pull-request, source-control]
runs: 3
max_turns: 15
allowed_tools: [Read, Glob, Grep, Skill, Bash]
expected_outcome: git stash push -u runs before any checkout or branch creation
---

PR 482 is merged. Reuse this worktree for the next task, but `git status --porcelain` shows tracked edits and an untracked file.
