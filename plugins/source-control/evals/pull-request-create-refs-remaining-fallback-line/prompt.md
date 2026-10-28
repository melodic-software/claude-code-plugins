---
description: A PR linked with Refs to an issue with no checklist, sub-issues or slice list gets a one-line Remaining section naming what closes the issue
tags: [pull-request, source-control]
plugins: ["../..", "gh-forge-path"]
runs: 3
max_turns: 30
allowed_tools: [Read, Glob, Grep, Skill, Bash, Write]
expected_outcome: The PR body written to a file opens with Refs: #820 and has a Remaining section with one line naming what this PR delivers and the condition that closes #820, with no closing keyword before #820 anywhere in the body
---

Open a draft PR for this branch. It is only the first step on issue #820, the byte order mark, so link it with `Refs: #820`; it must not close the issue. The unit tests pass. Skip prep.
