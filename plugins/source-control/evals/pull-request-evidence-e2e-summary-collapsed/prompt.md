---
description: Captures from e2e-summary.json files, which map no capture to an entry point, stay in collapsed sections even for a one-criterion change
tags: [pull-request, source-control, evidence]
plugins: ["../..", "gh-forge-path"]
runs: 3
max_turns: 40
timeout_seconds: 900
allowed_tools: [Read, Glob, Grep, Skill, Bash, Write]
expected_outcome: The evidence comment body written to a file opens with the text result, holds its captures inside a collapsed section, and has no Before/After table
---

The verifier passed PR 412's current head. Post its verification evidence comment. The head run's end-to-end summary is evidence/head/e2e-summary.json and the base run's is evidence/base/e2e-summary.json.
