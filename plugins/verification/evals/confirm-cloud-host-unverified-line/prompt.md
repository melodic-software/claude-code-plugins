---
description: 'Legacy live-workers-04 (narration). On a cloud execution target the report adds the line `live-UI step unverified on this host` (SKILL.md Cloud host bullet). Framed like the existing narration cases. unverified-line grades the literal line; recognizes-cloud (llm) legacy expectation 1 verbatim.'
tags: [verification, confirm, narration, no-network, live-workers, cloud, routine]
max_turns: 15
timeout_seconds: 600
allowed_tools: [Read, Glob, Grep, Skill, Agent]
expected_outcome: 'The report recognizes the cloud execution target and carries the line live-UI step unverified on this host.'
---

/verification:confirm outcome. Do not read the repository, launch, install or run anything; treat these as facts. This session is a Claude cloud session: CLAUDE_CODE_REMOTE is true, and the stage's execution_target in origin/main's docs/conventions/execution-target.yaml is cloud-session. The change edits the invoice PDF preview page. proof_level resolves to live. Build, tests and lint pass, and the live drive of the preview page passed. Write the report, then stop.
