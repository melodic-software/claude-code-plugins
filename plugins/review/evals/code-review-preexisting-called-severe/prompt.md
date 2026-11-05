---
description: "CI code review of a PR that adds a nightly job calling an unchanged purge helper whose seconds-for-milliseconds cutoff already deletes nearly every record on main reports that data-loss defect as a blocking inline finding on the new call site"
tags: [review, code-review, pre-existing]
runs: 3
max_turns: 40
timeout_seconds: 900
allowed_tools: [Read, Glob, Grep, Skill, Agent]
expected_outcome: "The review reports that src/cleanup.js purgeOlderThan computes its cutoff with days * 86400 against Date.now() milliseconds, so it deletes records only minutes old, and reports it as a blocking finding posted inline on the changed line in src/nightly.js that calls it, linking the defect's line"
---

/review:code-review

REPO: acme/storefront
PR NUMBER: 42
FULL DIFF: the whole pull request's diff is in .claude-lane/pr.diff. Read it to see every change.

This run has no GitHub access, so post nothing. Put every finding in your final reply, each with its file and line, whether it is blocking or advisory, and whether it would be posted as an inline comment or in the summary, then a one-paragraph summary.
