---
description: Commit a staged fix with a Conventional Commits subject, a stdin heredoc message, and a Co-authored-by trailer
tags: [commit, source-control]
runs: 3
max_turns: 15
allowed_tools: [Read, Glob, Grep, Skill, Bash]
expected_outcome: The commit is one git commit -F - --cleanup=verbatim call fed by a single-quoted heredoc, with a Conventional Commits subject and a --trailer Co-authored-by line
---

I've staged the fix for the null-user crash in the /me endpoint. Commit it.
