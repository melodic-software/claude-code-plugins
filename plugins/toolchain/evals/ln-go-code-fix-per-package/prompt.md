---
description: "Legacy lint 9. `--code-fix --yes go` drops go.mod, groups the .go paths by parent directory, and invokes the Go code-fix-cmd once per package directory, never one process with files from two directories. The tracked go.yaml routes code-fix-cmd through tools/run.sh, which logs one line per call to .calls.log. both-dirs-fixed, one-dir-per-call and no-module-files read that log; meets-expectations (llm) quotes the legacy expectations. Needs --scaffold --allow-tools Bash."
tags: [toolchain, lint, code-fix, go, scaffold, no-network]
max_turns: 25
timeout_seconds: 600
allowed_tools: [Skill, Read, Glob, Grep, Bash]
expected_outcome: "The go code-fix-cmd runs twice, once with pkg/a/a.go and once with pkg/b/b.go; no call carries both files or go.mod."
---

/toolchain:lint --code-fix --yes go
