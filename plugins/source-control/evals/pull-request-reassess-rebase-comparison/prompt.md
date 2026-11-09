---
description: A continue that rebases a reviewed PR posts one before-and-after comparison, after the push
tags: [pull-request, source-control]
plugins: ["../..", "gh-forge-path"]
runs: 1
max_turns: 45
timeout_seconds: 900
allowed_tools: [Read, Glob, Grep, Skill, Bash]
expected_outcome: The verdict is continue, the head branch is rebased with one force push, and one PR comment carries the range-diff
---

/source-control:pull-request reassess 512 --act
