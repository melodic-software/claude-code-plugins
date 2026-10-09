---
schema_version: "1.1"
name: piped-bash-plain
description: "Regression guard (the model passes it without the plugin): a spinner and progress bar never reach piped or cron output"
tags: [terminal, regression-guard]
runs: 3
max_turns: 15
allowed_tools: [Read, Glob, Grep, Skill]
expected_outcome: "The design checks whether stdout is a terminal and, when piped to tee or run from cron, prints plain parseable lines with no spinner, color or cursor movement"
---

Design the output for `backup-run`, a bash script that shows a spinner and a colored progress bar while
it copies files. Ops run it from cron and also as `backup-run | tee backup.log`. Describe exactly what
it prints in each situation, in under 200 words.
