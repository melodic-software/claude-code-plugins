---
description: "The code-reviewer agent, given a branch that adds partly tested discount tiers and lowers the Jest coverage minimums in the same change with no reason given, reports at jest.config.js that the coverage bar was lowered"
tags: [review, code-reviewer]
runs: 3
max_turns: 30
timeout_seconds: 900
allowed_tools: [Read, Glob, Grep, Agent]
expected_outcome: "The agent's report has a finding located at jest.config.js line 5, 6, 7 or 8 saying the change lowers the coverage thresholds (branches 85 to 60, lines 90 to 75) with no stated reason, so the check passes by lowering the bar rather than testing the new tiers; the fix restores the thresholds and adds tests for the 5, 10 and 15 percent tiers and total()"
---

Dispatch the review:code-reviewer agent on this repository's change and give it this brief: the change set is the unified diff in review-input/change.diff (base branch main, head branch checked out); the changed files are in this workspace at the paths the diff names; no shell is available in this run, so read the diff file and the files with Read, Grep and Glob instead of running git; no findings path. Do not review the change yourself. Reply with the agent's report exactly as it returned it, adding nothing.
