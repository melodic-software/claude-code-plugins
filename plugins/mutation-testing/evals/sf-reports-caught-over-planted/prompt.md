---
description: "A configured Python repo (tool: manual, test-command set) with three pricing functions and happy-path-only tests. seed-faults SKILL.md: plants three seeds one at a time in a throwaway worktree outside the repository (the grader checks the `git worktree add`, since the eval sandbox mounts .git read-only and the run then falls back to a copy outside the repository), never commits, never edits tests, and reports seeds caught over seeds planted with each survivor's file:line, as an estimate. A no-plugin model edits src/pricing.py in place and reports a count with no estimate caveat. Needs --scaffold --allow-tools Bash Edit Write."
tags: [mutation-testing, seed-faults, outcome, scaffold]
runs: 3
max_turns: 60
timeout_seconds: 1200
allowed_tools: [Skill, Bash, Read, Glob, Grep, Edit, Write]
expected_outcome: "Three seeds are planted one at a time in a throwaway worktree or copy outside the repository; no commit is made, no test file is edited, src/pricing.py is unchanged; the reply gives caught over 3 planted, names each surviving seed by src/pricing.py:<line>, and calls the ratio an estimate."
---

Plant 3 realistic bugs in this code and tell me how many of them my tests catch.
