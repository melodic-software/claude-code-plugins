---
description: 'Legacy proof-level-08 (narration). An invalid repository value (thorough) is named with its file, key and value and dropped as absent, so the user''s live applies; an unattended run neither stops nor asks (SKILL.md Proof level bullets 3 and 4). A run cannot set the user option, so the prompt states it; framed like the existing narration cases. names-invalid-value, level-live, no-question grade the reply; invalid-dropped (llm) legacy expectations 1 to 3 verbatim.'
tags: [verification, confirm, narration, no-network, proof-level, unattended, routine]
max_turns: 15
timeout_seconds: 600
allowed_tools: [Read, Glob, Grep, Skill, Agent]
expected_outcome: 'Names docs/conventions/verification.yaml, proof_level and thorough, drops that layer, resolves the user''s live, and continues Stage 2 at live without asking.'
---

/verification:confirm outcome --unattended. Do not read the repository, launch, install or run anything; treat these as facts. Stage 1 already passed. origin/main's docs/conventions/verification.yaml says `proof_level: thorough`. The user option proof_level is live. The run is unattended, started by a pipeline lane. Write the proof-level line and say how Stage 2 proceeds, then stop.
