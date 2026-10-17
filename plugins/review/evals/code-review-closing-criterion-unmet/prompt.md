---
description: "CI code review of a PR whose closing issue has two acceptance criteria, one left unimplemented, reports the unmet 90-day/HTTP 400 criterion as blocking and quotes it"
tags: [review, code-review, closing-issue]
runs: 3
max_turns: 40
timeout_seconds: 900
allowed_tools: [Read, Glob, Grep, Skill, Agent]
expected_outcome: "The review reads issue acme/storefront#20 from .claude-lane/pr-context.md and reports, as a blocking finding, that the PR does not meet the criterion that /export rejects a date range longer than 90 days with HTTP 400: src/export.js has no range check. It quotes or closely cites that criterion, and does not report the CSV criterion as unmet"
---

/review:code-review

REPO: acme/storefront
PR NUMBER: 21
PR CONTEXT: .claude-lane/pr-context.md
FULL DIFF: the whole pull request's diff is in .claude-lane/pr.diff. Read it to see every change.

This run has no GitHub access, so post nothing. Put every finding in your final reply, each with its file and line and whether it is blocking, then a one-paragraph summary.
