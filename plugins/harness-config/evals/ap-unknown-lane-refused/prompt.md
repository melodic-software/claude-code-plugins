---
description: "Routine. An unknown --lanes id is refused before any lane runs: SKILL.md Phase 3, 'A --lanes value naming an id outside that set is refused non-zero'; reference/arguments.md, 'refused non-zero, naming the unknown id and listing the ids this run would accept, rather than silently running a smaller set'. The valid ids are instructions:<class>, conflicts, permission-state, permission-grants, config, memory, retirements and postures. Source: the before SKILL.md and reference/arguments.md. Needs --scaffold --allow-tools Bash Write."
tags: [routine, audit-pass, outcome, refusal, scaffold]
runs: 3
max_turns: 15
timeout_seconds: 900
allowed_tools: [Skill, Read, Glob, Grep, Bash, Write]
expected_outcome: "The reply refuses, names `linting` as an unknown lane id and lists accepted ids including permission-state and conflicts; no delegated audit skill is invoked and no lease is taken."
---

/harness-config:audit-pass --lanes config,linting
