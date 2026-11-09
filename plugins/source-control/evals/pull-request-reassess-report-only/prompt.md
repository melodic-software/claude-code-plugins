---
description: A default run on a PR whose verdict would add a label and a comment changes nothing
tags: [pull-request, source-control]
plugins: ["../..", "gh-forge-path"]
runs: 1
max_turns: 45
timeout_seconds: 900
allowed_tools: [Read, Glob, Grep, Skill, Bash]
expected_outcome: A verdict is returned, and the call record shows the limits read and no write of any kind
---

/source-control:pull-request reassess 512
