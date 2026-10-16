---
description: With no setting and no request for a draft, create resolves the open state to ready and opens the PR as a draft for ready to flip
tags: [pull-request, source-control]
runs: 3
max_turns: 30
allowed_tools: [Read, Glob, Grep, Skill, Bash, Write]
expected_outcome: The reply reports the open state as ready from the default level, the PR is opened with the draft flag, and ready's gates are named as what flips it
---

Open a PR for this branch. Skip prep; there's no related issue, it's a small demo fix. Before you open it, tell me which open state you resolved and which level it came from.
