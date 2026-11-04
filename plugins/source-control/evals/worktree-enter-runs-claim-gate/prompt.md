---
description: Run the claim gate before writing in a worktree this session did not create
tags: [worktree, source-control]
runs: 3
max_turns: 15
allowed_tools: [Read, Glob, Grep, Skill, Bash]
expected_outcome: worktree-claim.sh check-enter runs on the existing worktree
---

With the source-control:worktree skill, get ready to write in the existing worktree at ../eval-linked, which this session did not create. Do not edit anything yet.
