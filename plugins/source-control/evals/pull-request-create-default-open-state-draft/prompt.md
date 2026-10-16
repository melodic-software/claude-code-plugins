---
description: With no setting and no request for a draft, create resolves the open state to draft from the default and does not run ready
tags: [pull-request, source-control]
runs: 3
max_turns: 30
allowed_tools: [Read, Glob, Grep, Skill, Bash, Write]
expected_outcome: The reply reports the open state as draft from the default level and names /source-control:pull-request ready as what flips it later
---

I'm driving this session and will answer any prompt. Open a PR for this branch. Skip prep; there's no related issue, it's a small demo fix. Before you open it, tell me which open state you resolved and which level it came from.
