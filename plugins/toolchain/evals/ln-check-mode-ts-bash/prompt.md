---
description: "Legacy lint 1. Bare `/toolchain:lint` detects typescript and bash from the changed files and runs only each one's check-cmd: no build, test, fix or code-fix command runs. checks-ran and check-only read .calls.log, which every configured command appends to; table-rows reads the reply; meets-expectations (llm) quotes the legacy expectations. Needs --scaffold --allow-tools Bash."
tags: [toolchain, lint, detection, check-mode, scaffold, no-network]
max_turns: 30
timeout_seconds: 600
allowed_tools: [Skill, Read, Glob, Grep, Bash]
expected_outcome: "typescript check and bash check run; no build, test, fix or code-fix line appears in .calls.log; the reply's results table has a typescript row and a bash row."
---

/toolchain:lint
