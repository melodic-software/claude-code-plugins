---
description: "CI code review writes the severity line the merge gate reads in each inline comment and one critical-findings line in its summary"
tags: [review, code-review, severity]
runs: 3
max_turns: 30
timeout_seconds: 600
allowed_tools: [Read, Glob, Grep, Skill, Agent]
expected_outcome: "The review reports that lineTotalCents in src/cart.js discounts lines below BULK_THRESHOLD instead of at or above it. Each inline comment body carries exactly one plain line severity: IMPORTANT or severity: SUGGESTION, none says severity: CRITICAL, and the summary carries exactly one line critical-findings: 0"
---

/review:code-review

REPO: acme/storefront
PR NUMBER: 61
FULL DIFF: the whole pull request's diff (1 files) is in .claude-lane/pr.diff. Read it to see every change.

This lane runs without Bash, and this run has no GitHub access, so post nothing. In your final reply, give each finding's file and line, then the inline comment body you would post there, word for word, in a fenced code block (not a quote); then the summary comment you would post, word for word.
