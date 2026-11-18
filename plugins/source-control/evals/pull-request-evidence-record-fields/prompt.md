---
description: With evidence_record_fields on in the base's team config, the evidence comment carries who verified, when, and the issues found
tags: [pull-request, source-control, evidence]
plugins: ["../..", "gh-forge-path"]
runs: 3
max_turns: 40
timeout_seconds: 900
allowed_tools: [Read, Glob, Grep, Skill, Bash, Write]
expected_outcome: The evidence comment body written to a file names Dana Okafor as the verifier, a UTC date and time, and an issues-found line
---

The verifier passed PR 412's current head; Dana Okafor ran the verification. With the pull-request skill, post its verification evidence comment. The head run's drive report is evidence/head/report.json and the base run's is evidence/base/report.json.
