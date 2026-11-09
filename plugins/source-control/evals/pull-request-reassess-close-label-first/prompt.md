---
description: Acting on a close adds do-not-merge, then posts one comment, and never closes the PR
tags: [pull-request, source-control]
plugins: ["../..", "gh-forge-path"]
runs: 1
max_turns: 45
timeout_seconds: 900
allowed_tools: [Read, Glob, Grep, Skill, Bash]
expected_outcome: The call record holds the do-not-merge label edit before exactly one PR comment, and no gh pr close is run
---

/source-control:pull-request reassess 512 --act
