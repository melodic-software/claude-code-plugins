---
description: A PR whose goal and implementation still hold gets continue
tags: [pull-request, source-control]
plugins: ["../..", "gh-forge-path"]
runs: 2
max_turns: 45
timeout_seconds: 900
allowed_tools: [Read, Glob, Grep, Skill, Bash]
expected_outcome: The verdict is continue, with the goal, its source, the base range and the PRs searched
---

/source-control:pull-request reassess 512
