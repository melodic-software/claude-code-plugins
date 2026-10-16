---
description: The drafted PR body carries the PLAN.md Brief's acceptance criteria under an Acceptance criteria section
tags: [pull-request, source-control, intent-ladder]
runs: 3
max_turns: 30
allowed_tools: [Read, Glob, Grep, Skill, Bash, Write]
expected_outcome: The PR body written to a file has a section headed Acceptance criteria that lists the plan Brief's three criteria (byte order mark, RFC 4180 quoting, header row with no rows) as values, with no path into the .work memory slice
---

Open a draft PR for this branch. The unit tests pass. Skip prep; there's no related issue.
