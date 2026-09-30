---
description: Commit only; push and PR creation belong to the pull-request skill
tags: [commit, source-control]
runs: 3
max_turns: 15
allowed_tools: [Read, Glob, Grep, Skill, Bash]
expected_outcome: No git push and no gh pr create; the reply points at the pull-request skill
---

Commit this and then push it and open a PR.
