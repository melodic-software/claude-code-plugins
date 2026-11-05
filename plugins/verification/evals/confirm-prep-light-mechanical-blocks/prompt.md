---
description: "Under verification: light set on the default branch, a change whose unit test fails is still blocked at the PR-prep gate: the skip exception never covers a Stage 1 failure"
tags: [confirm, setting, verification-level, pr-prep]
runs: 3
max_turns: 40
timeout_seconds: 900
allowed_tools: [Read, Glob, Grep, Skill, Bash, Agent]
expected_outcome: "Stage 1 runs the unit tests, reports the failing slugify test, and says the gate blocks PR creation; the light level does not excuse it"
---

/verification:confirm This run is the verify gate of /source-control:pull-request prep. End the report with one line saying whether the gate blocks PR creation.
