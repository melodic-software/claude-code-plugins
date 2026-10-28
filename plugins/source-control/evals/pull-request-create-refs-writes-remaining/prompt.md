---
description: A PR linked with Refs gets a Remaining section listing the issue's open items and leaving out what it delivers
tags: [pull-request, source-control]
plugins: ["../..", "gh-forge-path"]
runs: 3
max_turns: 30
allowed_tools: [Read, Glob, Grep, Skill, Bash, Write]
expected_outcome: "The PR body written to a file opens with Refs: #812, has a Remaining section listing the RFC 4180 quoting item as a plain bullet without its Closes #813 text, and leaves the checked header-row item and the delivered byte order mark out of that section"
---

Open a draft PR for this branch. It delivers only the byte order mark from issue #812, so link it with `Refs: #812`; it must not close the issue. The unit tests pass. Skip prep.
