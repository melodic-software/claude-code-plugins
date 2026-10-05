---
description: "Phase 1 first: an observed failure gets a reproduction loop before any cause is guessed"
tags: [debug, converted]
runs: 3
max_turns: 15
timeout_seconds: 600
allowed_tools: [Read, Glob, Grep, Skill]
expected_outcome: "Starts at Phase 1 by building a fast, deterministic, agent-runnable pass/fail reproduction loop and gates Phase 2 on it; proposes no fix or root cause first"
---

/debugging:debug checkout times out for orders over $1,000 but works fine for small orders.
