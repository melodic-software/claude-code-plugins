---
description: With no setting and no request for a draft, create resolves the open state to ready from the default and runs ready on the new PR
tags: [pull-request, source-control]
runs: 3
max_turns: 30
allowed_tools: [Read, Glob, Grep, Skill, Bash, Write]
expected_outcome: The reply reports the open state as ready from the default level and runs or starts /source-control:pull-request ready on the new PR
---

I'm driving this session and will answer any prompt. Open a PR for this branch. Skip prep; there's no related issue, it's a small demo fix. Before you open it, tell me which open state you resolved and which level it came from.
