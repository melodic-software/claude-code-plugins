---
description: Create a worktree through worktree-create.sh and report its path
tags: [worktree, source-control]
runs: 3
max_turns: 15
allowed_tools: [Read, Glob, Grep, Skill, Bash, Write]
expected_outcome: worktree-create.sh runs with the requested name, and the reply names the created path or the helper's refusal
---

Create a worktree named feat/payment-retry so I have an isolated checkout for this feature.
