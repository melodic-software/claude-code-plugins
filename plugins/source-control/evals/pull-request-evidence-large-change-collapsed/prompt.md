---
description: A three-criterion change keeps one collapsed section per acceptance criterion, under the text result, each capture labeled with its run
tags: [pull-request, source-control, evidence]
plugins: ["../..", "gh-forge-path"]
runs: 3
max_turns: 40
timeout_seconds: 900
allowed_tools: [Read, Glob, Grep, Skill, Bash, Write]
expected_outcome: The evidence comment body written to a file opens with the text result under its heading and holds three collapsed sections, each capture labeled Before or After, and no Before/After table
---

The verifier passed PR 412's current head. Post its verification evidence comment. The head run's drive report is evidence/head/report.json and the base run's is evidence/base/report.json.
