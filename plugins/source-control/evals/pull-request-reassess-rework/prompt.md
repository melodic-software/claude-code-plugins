---
description: A PR whose goal still holds but whose implementation calls a function the base removed gets rework
tags: [pull-request, source-control]
plugins: ["../..", "gh-forge-path"]
runs: 2
max_turns: 45
timeout_seconds: 900
allowed_tools: [Read, Glob, Grep, Skill, Bash]
expected_outcome: The verdict is rework, citing PR 588, which renamed the function the head calls, with the goal, its source, the base range and the PRs searched
---

/source-control:pull-request reassess 512
