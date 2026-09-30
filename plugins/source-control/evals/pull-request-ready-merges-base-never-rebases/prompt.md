---
description: Flip a draft to ready by merging the base and verifying last
tags: [pull-request, source-control]
runs: 3
max_turns: 25
allowed_tools: [Read, Glob, Grep, Skill, Bash]
expected_outcome: The base is merged, never rebased, and verification:confirm runs before gh pr ready
---

PR 512 is an open draft on this branch, main has moved ahead of it, and the last verification ran two commits ago. Flip it to ready for review.
