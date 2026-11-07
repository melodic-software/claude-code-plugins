---
description: 'Legacy proof-level-06 (narration). Under strict with no baseline and no performance plugin, the perf box reads `NOT VERIFIED: no baseline` and the verdict is NOT VERIFIED though the unit and live boxes hold evidence (context/outcome.md Proof boxes, Verdict under strict). Framed like the existing narration cases. perf-box-line, verdict-not-verified grade the reply; no-baseline-gap (llm) legacy expectations 1 to 3 verbatim.'
tags: [verification, confirm, narration, no-network, proof-level, proof-boxes, routine]
max_turns: 15
timeout_seconds: 600
allowed_tools: [Read, Glob, Grep, Skill, Agent]
expected_outcome: 'The perf box reads NOT VERIFIED: no baseline, naming no planning-time baseline and no performance plugin; the verdict is NOT VERIFIED and names the phase and the perf box; no performance number is invented.'
---

/verification:confirm outcome. Do not read the repository, launch, install or run anything; treat these as facts. Stage 1 already passed this conversation. proof_level resolves to strict. The diff rewrites the search index's tokenizer loop, a runtime code path. No /verification:measure baseline was captured at planning time, and the performance plugin is not enabled. Unit tests and a live drive both pass. Write the report and verdict, then stop.
