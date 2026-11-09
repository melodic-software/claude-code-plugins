---
description: Flip a draft to ready; the branch update decision picks a merge here, and verification runs last
tags: [pull-request, source-control]
plugins: ["../..", "gh-forge-path"]
runs: 3
max_turns: 25
timeout_seconds: 900
allowed_tools: [Read, Glob, Grep, Skill, Bash]
expected_outcome: The branch update decision picks a merge (no rebase on this squash-landing repository, whichever row it matched, and the rule is reported), so the base is merged and not rebased, and the merge runs before gh pr ready
---

PR 512 is an open draft on this branch, main has moved ahead of it on a file this branch also changes, and the last verification ran two commits ago. Flip it to ready for review.
