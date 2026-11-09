---
description: A PR already carrying do-not-merge gets only an edit of the action's own earlier comment
tags: [pull-request, source-control]
plugins: ["../..", "gh-forge-path"]
runs: 1
max_turns: 45
timeout_seconds: 900
allowed_tools: [Read, Glob, Grep, Skill, Bash]
expected_outcome: The call record holds one edit of comment 9001, the acting login's own marked comment, and no new comment, label edit or push
---

/source-control:pull-request reassess 512 --act
