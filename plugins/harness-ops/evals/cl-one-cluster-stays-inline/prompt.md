---
description: "A two-release diff with three items, one a behavioral change the scaffolded skill states, so Phase 1 explores and Phase 2 research is reached. One release cluster and one feature cluster: explore and research stay in this session; only the local verifier may run as a subagent. Reaches SKILL.md 'Phase 1. Explore', 'Phase 2. Research' step 1 and context/decisions.md 'Fan-out shape'. Source: the consumer's own writing (a small release). routine: on Opus 5.5 the current text already kept explore and research in-session. Needs --scaffold --allow-tools Bash (Agent granted for the no-spawn grader). Held-rows rows: harness-ops 48, 49."
tags: [harness-ops, changelog, delegation, no-network, routine]
max_turns: 40
timeout_seconds: 900
allowed_tools: [Skill, Read, Glob, Grep, Bash, Agent]
expected_outcome: "The skill runs changelog-status.sh on v2.1.260..v2.1.261 with the local changelog, explores and researches the three items in this session without spawning an explorer or researcher (the local verifier may run), and emits a correct row for skills/notes/SKILL.md (its 80% compaction claim)."
---

/harness-ops:changelog diff v2.1.260..v2.1.261

This machine has no network. A complete copy of the changelog is at ./changelog.md; use it instead of fetching.
