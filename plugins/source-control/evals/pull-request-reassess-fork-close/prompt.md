---
description: Acting on a close for a fork head adds the label and comment and pushes nothing
tags: [pull-request, source-control]
plugins: ["../..", "gh-forge-path"]
runs: 1
max_turns: 45
timeout_seconds: 900
allowed_tools: [Read, Glob, Grep, Skill, Bash]
expected_outcome: The call record holds the do-not-merge label edit before one PR comment, and no push and no update-branch attempt
---

/source-control:pull-request reassess 512 --act
