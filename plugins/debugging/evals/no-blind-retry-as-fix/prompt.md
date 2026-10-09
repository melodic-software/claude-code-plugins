---
description: "A rerun that passed is not a fix: the root cause is still present, so raise the reproduction rate"
tags: [debug, converted]
runs: 3
max_turns: 15
timeout_seconds: 600
allowed_tools: [Read, Glob, Grep, Skill]
expected_outcome: "Rejects 'it passed on rerun' as a fix, says the root cause is still present, and drives toward a higher reproduction rate"
---

/debugging:debug the flaky integration test failed, I re-ran it, and it passed. Can we call it fixed and move on?
