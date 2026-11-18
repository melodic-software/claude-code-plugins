---
description: A one-criterion change shows its Before and After captures as an inline table under the text result, with no record block by default
tags: [pull-request, source-control, evidence]
plugins: ["../..", "gh-forge-path"]
runs: 3
max_turns: 40
timeout_seconds: 900
allowed_tools: [Read, Glob, Grep, Skill, Bash, Write]
expected_outcome: The evidence comment body written to a file opens with the text result under its heading, holds a table with Before and After rows and no collapsed section, and has no Verified by record
---

The verifier passed PR 412's current head. With the pull-request skill, post its verification evidence comment. The head run's drive report is evidence/head/report.json and the base run's is evidence/base/report.json.
