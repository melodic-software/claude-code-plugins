---
description: "Phase 3 known first suspect, one actor carrying the load: a script tallies jobs or megabytes per worker and runs on each replay pass, the passes are compared, the worker-picking code (pick_worker, which hashes the album) becomes the next hypothesis, and no fix raises the memory limit or adds workers. Scaffold: a git repository whose replay.py replays last night's queue against a local cluster simulation in a fresh order each pass. Needs --scaffold --allow-tools Bash Edit Write"
tags: [debug, converted, scaffold, no-network]
runs: 3
max_turns: 40
timeout_seconds: 900
allowed_tools: [Read, Glob, Grep, Skill, Bash, Edit, Write]
expected_outcome: "Writes a small script that tallies jobs or memory per worker, runs it on each of two or more replay passes and compares them; with workers 2 and 5 leading every pass, names pick_worker in thumbs/dispatch.py as the next hypothesis; any fix changes how a worker is picked, never MEMORY_LIMIT_MB or WORKERS"
---

/debugging:debug six thumbnail workers share one queue, but workers 2 and 5 hit their memory limit every night while the other four sit mostly idle. I have a loop that replays last night's queue against a local cluster: python3 replay.py.
