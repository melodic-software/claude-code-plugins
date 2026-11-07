---
description: 'Legacy proof-level-03 (narration). The user''s strict outranks the repository''s path, the report line names userConfig, and the report carries a proof-box table with unit, live and perf boxes for each of the two phases (context/outcome.md Proof boxes). A run cannot set the user option, so the prompt states it; framed like the existing narration cases. report-line-strict, proof-box-table grade the reply; user-strict-boxes (llm) legacy expectations 1 to 3 verbatim.'
tags: [verification, confirm, narration, no-network, proof-level, proof-boxes, routine]
max_turns: 15
timeout_seconds: 600
allowed_tools: [Read, Glob, Grep, Skill, Agent]
expected_outcome: 'Reports proof_level: strict from userConfig, noting the repository says path, and a proof-box table with unit, live and perf boxes for both phases, each filled or given a reasoned not-applicable line.'
---

/verification:confirm outcome. Do not read the repository, launch, install or run anything; treat these as facts. Stage 1 already passed this conversation. The user option proof_level is strict. origin/main's docs/conventions/verification.yaml says `proof_level: path`. The approved plan has two phases: a new invoice-total calculation and its export endpoint. Write the report, then stop.
