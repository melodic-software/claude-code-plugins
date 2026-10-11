---
description: The drafted PR body's Verification section ends with a Left out line
tags: [pull-request, source-control]
runs: 3
max_turns: 30
allowed_tools: [Read, Glob, Grep, Skill, Bash, Write]
expected_outcome: The PR body written to a file has a Verification section whose last line starts with Left out and names the skipped end-to-end suite with its reason
---

Open a draft PR for this branch. The unit tests pass; I didn't run the end-to-end suite because it needs a staging environment we don't have. Skip prep; there's no related issue, it's a small demo fix.
