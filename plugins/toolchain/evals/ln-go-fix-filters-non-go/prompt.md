---
description: "Legacy lint 8. `--fix go` substitutes only *.go paths into the Go fix-cmd: pkg/a.go reaches it, go.mod and go.sum never do. The tracked go.yaml routes fix-cmd through tools/run.sh, which logs its arguments to .calls.log. fixed-go-file and no-module-files read that log; meets-expectations (llm) quotes legacy expectations 1 and 2 (3, the zero-.go skip, is a counterfactual this tree cannot show). Needs --scaffold --allow-tools Bash."
tags: [toolchain, lint, fix, go, scaffold, no-network]
max_turns: 25
timeout_seconds: 600
allowed_tools: [Skill, Read, Glob, Grep, Bash]
expected_outcome: "The go fix-cmd runs once with pkg/a.go and without go.mod or go.sum; the code-fix-cmd never runs."
---

/toolchain:lint --fix go
