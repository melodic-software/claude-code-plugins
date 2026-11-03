---
description: Monitoring a PR arms a Monitor watch at the deadline maximum whose poll covers every review surface
tags: [pull-request, source-control]
plugins: ["../..", "gh-forge-path"]
runs: 3
max_turns: 30
timeout_seconds: 900
allowed_tools: [Read, Glob, Grep, Skill, Bash, Monitor]
expected_outcome: A Monitor watch for PR 517 is armed with timeout_ms 1800000, and its command polls issue-level comments, inline review comments and reviews, not checks alone
---

Monitor PR 517 with the pull-request skill. Nothing has reported on it yet; CI and the reviewers will post over the next while. Keep watching it and tell me what comes in.
