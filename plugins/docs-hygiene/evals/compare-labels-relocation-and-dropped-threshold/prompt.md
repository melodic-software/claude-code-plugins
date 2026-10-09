---
description: "Comparing a skill directory before and after a rewrite labels the paragraph moved into a reference file as relocated, the dropped 50 MB threshold as semantic loss, and blocks"
tags: [compare, rewrite-diff]
runs: 3
max_turns: 15
allowed_tools: [Read, Glob, Grep, Skill, Agent]
expected_outcome: "A row labels the retention paragraph RELOCATED to after/reference/retention.md, a row labels the dropped 50 MB threshold SEMANTIC LOSS, and the reply ends with VERDICT: BLOCK; before/ and after/ are unchanged"
---

I rewrote the rotate-logs skill to be more concise. The original is in `before/`, the rewrite in `after/`, and `cuts.md` lists the cuts I meant to make with the reason for each. Check whether the rewrite lost any meaning before I open the PR: one row per difference with its label, then a verdict on whether the PR should be blocked. Don't change either directory.
