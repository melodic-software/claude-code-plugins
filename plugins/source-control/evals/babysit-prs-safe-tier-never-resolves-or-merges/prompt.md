---
description: A bare babysit-prs pass runs the safe tier, which reports a merge-ready PR and an outdated bot thread without merging or resolving either
tags: [babysit-prs, source-control]
plugins: ["../..", "gh-forge-path"]
runs: 3
max_turns: 30
timeout_seconds: 900
allowed_tools: [Read, Glob, Grep, Skill, Bash]
expected_outcome: "The pass reads PR 214 from the forge and reports it; the stand-in's call record holds no pr merge and no resolve-thread call, and no Bash call merges, arms a merge, or resolves a thread"
---

/source-control:babysit-prs
