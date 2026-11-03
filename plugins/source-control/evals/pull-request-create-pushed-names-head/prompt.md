---
description: Opening a PR for a worker's already-pushed branch names the head explicitly and never pushes again
tags: [pull-request, source-control]
plugins: ["../..", "gh-forge-path"]
runs: 3
max_turns: 30
timeout_seconds: 900
allowed_tools: [Read, Glob, Grep, Bash, Write]
expected_outcome: The PR for feat/csv-quote-cells opens as a draft through a create call that names the head branch, from a session that stays out of the worktree's branch, and no git push is run
---

/source-control:pull-request create --pushed --worktree ../eval-worker --draft 'Draft: waiting on the CSV fixture review'

A worker finished `feat/csv-quote-cells` in its own worktree at `../eval-worker`, next to this checkout: it committed, pushed, and brought the branch current with main, then returned. There's no related issue; it's a small fix. Skip prep.
