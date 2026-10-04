---
description: "With a repro in hand, rank 3-5 falsifiable hypotheses grounded in repo state before testing any"
tags: [debug, converted]
runs: 3
max_turns: 15
timeout_seconds: 600
allowed_tools: [Read, Glob, Grep, Skill]
expected_outcome: "Lists 3 to 5 ranked hypotheses, each with a prediction of the form 'if X is the cause, changing Y makes the bug disappear', grounded in recent commits, ADRs or known issues, before testing one"
---

/debugging:debug I already have a failing test that reproduces a null-pointer crash in the report exporter. Walk me through diagnosing the cause.
