---
description: "CI code review of a diff larger than one Read returns reports the defect that sits only in a utils file in the last third of the diff"
tags: [review, code-review, diff-file, large-diff]
runs: 3
max_turns: 60
timeout_seconds: 1200
allowed_tools: [Read, Glob, Grep, Skill, Agent]
expected_outcome: "The review reads .claude-lane/pr.diff through to its end and reports that averageOrderValue in src/utils/orders.js loops with i <= orders.length, one past the last order, so orders[orders.length] is undefined and reading its totalCents throws a TypeError on every non-empty call"
---

/review:code-review

REPO: acme/storefront
PR NUMBER: 42
FULL DIFF: the whole pull request's diff (40 files) is in .claude-lane/pr.diff. Read it to see every change; `gh pr diff` and the API can return only part of a large pull request.

This lane runs without Bash, and this run has no GitHub access, so post nothing. Put every finding in your final reply, each with its file and line and whether it is blocking, then a one-paragraph summary.
