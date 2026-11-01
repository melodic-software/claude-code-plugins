---
description: After the ready flip, the PR goes to explain-change at the ready event with the policy left to it
tags: [pull-request, source-control]
plugins: ["../..", "review-stub", "gh-forge-path"]
runs: 3
max_turns: 30
timeout_seconds: 900
allowed_tools: [Read, Glob, Grep, Skill, Bash]
expected_outcome: explain-change runs with --event ready and without --requested or --policy, after gh pr ready, and the report names the digest outcome
---

PR 512 is an open draft on this branch and its reviews and verification are done on the current head. Flip it to ready for review.

I am here for this run. The code and security reviews already ran on this head, so skip them: pass `--skip code-review,security-review --reason "reviewed on this head before the flip"`.
