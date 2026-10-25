---
description: "CI code review of a diff larger than one Read returns reports the defect in a service file in the middle of the diff, past the first page and before its tail"
tags: [review, code-review, diff-file, large-diff]
runs: 3
max_turns: 60
timeout_seconds: 1200
allowed_tools: [Read, Glob, Grep, Skill, Agent]
expected_outcome: "The review reads the middle of .claude-lane/pr.diff and reports that reserveStock in src/services/product-service.js adds the reserved quantity to stockLevel instead of subtracting it, so reserving stock increases it, the same as releaseStock does"
---

/review:code-review

REPO: acme/storefront
PR NUMBER: 42
FULL DIFF: the whole pull request's diff (40 files) is in .claude-lane/pr.diff. Read it to see every change; `gh pr diff` and the API can return only part of a large pull request.

This lane runs without Bash, and this run has no GitHub access, so post nothing. Put every finding in your final reply, each with its file and line and whether it is blocking, then a one-paragraph summary.
