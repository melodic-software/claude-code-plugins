---
description: "check in a repository whose go record holds a lint-cmd. setup SKILL.md Purpose and check step 5: the format row resolves to the goimports adapter, ungated; lint has no shipped adapter, so the hooks run nothing for it; the go record is never run by a hook, and /toolchain:lint or /toolchain:check runs it on request. resolve-ran is the with-only sign step 5 asked the resolver. Needs --scaffold --allow-tools Bash Write Edit so the must-not graders can fail."
tags: [go-format, setup, check, read-only, no-network]
max_turns: 14
timeout_seconds: 360
allowed_tools: [Read, Glob, Grep, Skill, Bash, Write, Edit]
expected_outcome: "format.sh --resolve runs; no Write or Edit. Formatting resolves to goimports; the hooks run nothing for Go linting because the plugin ships no lint adapter; the go record's lint-cmd is not run by hooks, and /toolchain:lint or /toolchain:check runs it on request."
---

/go-format:setup check

Our repo has a go record with a lint-cmd in it. Will go-format run that linter after edits or at commit?
