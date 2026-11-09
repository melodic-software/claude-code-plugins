---
description: A green, mergeable PR whose change already landed on the base gets close, naming what replaced it
tags: [pull-request, source-control]
plugins: ["../..", "gh-forge-path"]
runs: 2
max_turns: 45
timeout_seconds: 900
allowed_tools: [Read, Glob, Grep, Skill, Bash]
expected_outcome: The verdict is close and names PR 501 or its commit as the replacement, with the goal, its source, the base range and the PRs searched
---

/source-control:pull-request reassess 512
