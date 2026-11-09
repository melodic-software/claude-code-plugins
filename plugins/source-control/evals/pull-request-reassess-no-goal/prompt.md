---
description: A PR that states no goal gets no verdict and no write, even under --act and with its change already landed
tags: [pull-request, source-control]
plugins: ["../..", "gh-forge-path"]
runs: 1
max_turns: 45
timeout_seconds: 900
allowed_tools: [Read, Glob, Grep, Skill, Bash]
expected_outcome: The run reports that it gives no verdict because no goal is stated, returns no verdict, and writes nothing
---

/source-control:pull-request reassess 512 --act
