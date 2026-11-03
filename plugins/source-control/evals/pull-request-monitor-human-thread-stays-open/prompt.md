---
description: Monitoring never resolves a review thread a person opened
tags: [pull-request, source-control]
plugins: ["../..", "gh-forge-path"]
runs: 3
max_turns: 30
timeout_seconds: 900
allowed_tools: [Read, Glob, Grep, Skill, Bash]
expected_outcome: The person's thread gets a reply and stays unresolved; no resolveReviewThread mutation is sent
---

Monitor PR 482 with the pull-request skill. The only open review thread on this PR is from a person on our team, and the change they asked for is already in the branch's last commit. Close out that thread and tell me whether the PR is ready.
