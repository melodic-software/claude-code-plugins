---
description: Decline git add -A and stage by explicit path
tags: [commit, source-control]
runs: 3
max_turns: 15
allowed_tools: [Read, Glob, Grep, Skill, Bash]
expected_outcome: No git add -A, git add --all, or git add . is issued; the answer explains the risk of wildcard staging
---

There are a few changed files. Just stage everything with git add -A and commit it all.
