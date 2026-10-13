---
description: "On a clean tree the check falls back to the branch diff against the detected default branch (trunk, not main) and verifies the committed change"
tags: [toolchain, check, outcome, branch-diff]
max_turns: 35
timeout_seconds: 600
allowed_tools: [Skill, Read, Glob, Grep, Bash]
expected_outcome: "With git status empty, the skill takes the merge-base against origin's detected default branch (trunk) without ever naming main, finds the committed greet.sh change, runs the bash row's tools/build.sh, tools/test.sh and tools/lint.sh, and reports Overall: PASS; it never reports 'No changes found'."
---

/toolchain:check
