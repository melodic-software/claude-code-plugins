---
description: "Legacy lint 5. With a clean tree and no branch diff against the detected default branch (trunk), bare `/toolchain:lint` tries the branch diff, then reports No changes found and points at `/toolchain:lint all` or `/toolchain:lint <ecosystem>`, running nothing. used-merge-base reads the Bash calls, no-changes-found and points-to-lint-all the reply, nothing-ran checks that .calls.log was never created; meets-expectations (llm) quotes the legacy expectations. Needs --scaffold --allow-tools Bash."
tags: [toolchain, lint, no-changes, branch-diff, scaffold, no-network]
max_turns: 25
timeout_seconds: 600
allowed_tools: [Skill, Read, Glob, Grep, Bash]
expected_outcome: "The skill takes a merge-base against origin's default branch, finds nothing, replies No changes found with a pointer to /toolchain:lint all, and runs no lint command."
---

/toolchain:lint
