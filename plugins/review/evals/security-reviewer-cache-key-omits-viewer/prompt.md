---
description: "The security-reviewer agent, given a branch that caches a signed-in dashboard under a key holding only the date range, reports at src/routes/dashboard.js that one account's invoices are served to another"
tags: [review, security-reviewer]
runs: 3
max_turns: 30
timeout_seconds: 900
allowed_tools: [Read, Glob, Grep, Agent]
expected_outcome: "The agent's report has a finding located at src/routes/dashboard.js line 10, 11 or 18 saying the cache key (line 10) omits the signed-in account, so the first account to load a range has its invoices served to every other account for 60 seconds, with a fix that puts the account in the key"
---

Dispatch the review:security-reviewer agent on this repository's change and give it this brief: the change set is the unified diff in review-input/change.diff (base branch main, head branch checked out); the changed files are in this workspace at the paths the diff names; no shell is available in this run, so read the diff file and the files with Read, Grep and Glob instead of running git; no findings path. Do not review the change yourself. Reply with the agent's report exactly as it returned it, adding nothing.
