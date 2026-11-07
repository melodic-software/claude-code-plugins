---
description: "Legacy check 1. Detection matches the changed files against each ecosystem's globs: the changed .cs and .py files select dotnet and python, each runs build, test, then lint, and the unchanged powershell ecosystem never runs. phases-in-order and powershell-not-run read .calls.log, which the scaffold's tools/run.sh appends to; table-rows reads the reply; meets-expectations (llm) quotes the legacy expectations. Needs --scaffold --allow-tools Bash."
tags: [toolchain, check, detection, scaffold, no-network]
max_turns: 35
timeout_seconds: 600
allowed_tools: [Skill, Read, Glob, Grep, Bash]
expected_outcome: "dotnet and python each run build, test and lint in that order through their tracked configs; powershell runs nothing; the reply's results table has a dotnet row and a python row."
---

/toolchain:check
