---
description: 'Legacy live-workers-01 (narration). An unrendered ${user_config.live_workers} placeholder reads as unset and the repository file has no live_workers key, so live_workers resolves 1 from the default and one worker drives all four entry points (SKILL.md Live workers; config.md line 119 example). Framed like the existing narration cases. report-line grades `live_workers: 1 (default)`; one-worker (llm) legacy expectations 1 to 3 verbatim.'
tags: [verification, confirm, narration, no-network, live-workers, routine]
max_turns: 15
timeout_seconds: 600
allowed_tools: [Read, Glob, Grep, Skill, Agent]
expected_outcome: 'Reports live_workers: 1 (default), treats the placeholder as unset rather than invalid, and runs one worker over all four entry points.'
---

/verification:confirm outcome. Do not read the repository, launch, install or run anything; treat these as facts. The change edits the recipe search box. The user option live_workers renders as the literal text ${user_config.live_workers}, and origin/main's docs/conventions/verification.yaml sets only `proof_level: live`. The repository has a feature map whose Search recipes feature lists four entry points. Build, tests and lint pass. Write the worker line and say how the live drive is split, then stop.
