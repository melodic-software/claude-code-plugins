---
description: "assess on 'three agents each write a fix, keep one' with no selection rule reports a race with no rule stated and says the race must not start until one is, spawning nothing"
tags: [multi-agent, assess, outcome, race]
runs: 3
max_turns: 8
timeout_seconds: 300
allowed_tools: [Skill, Read, Bash, Agent]
expected_outcome: "verdict: subagent; shape: race (no selection rule stated); the reason line says the race must not start until a selection rule is stated. No agent is spawned."
---

/multi-agent:assess Have three agents each independently write a fix for the flaky login test in tests/auth/login.spec.ts, then keep one of the fixes.
