---
description: "CI code review of a PR that adds a caller of an unchanged helper whose missing-last-name bug already reproduces on main reports that bug as advisory in the summary, not as a blocking or inline finding"
tags: [review, code-review, pre-existing]
runs: 3
max_turns: 40
timeout_seconds: 900
allowed_tools: [Read, Glob, Grep, Skill, Agent]
expected_outcome: "The review reports that src/names.js formatName renders 'Ada undefined' for a user with no last name, says the defect predates this change (src/profile.js already calls it on main), and reports it as an advisory summary finding with no inline comment, never as blocking"
---

/review:code-review

REPO: acme/storefront
PR NUMBER: 41
FULL DIFF: the whole pull request's diff is in .claude-lane/pr.diff. Read it to see every change.

This run has no GitHub access, so post nothing. Put every finding in your final reply, each with its file and line, whether it is blocking or advisory, and whether it would be posted as an inline comment or in the summary, then a one-paragraph summary.
