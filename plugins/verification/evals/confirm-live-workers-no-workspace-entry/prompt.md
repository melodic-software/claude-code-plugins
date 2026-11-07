---
description: 'Legacy live-workers-03 (narration). live_workers 3 from userConfig, but with no Workspace environment entry on origin''s default branch one worker drives every entry point and the report says why (SKILL.md Local workers need a Workspace environment entry). A run cannot set the user option, so the prompt states it; framed like the existing narration cases. report-line, names-missing-entry grade the reply; one-worker-why (llm) legacy expectations 1 to 3 verbatim.'
tags: [verification, confirm, narration, no-network, live-workers, routine]
max_turns: 15
timeout_seconds: 600
allowed_tools: [Read, Glob, Grep, Skill, Agent]
expected_outcome: 'live_workers: 3 from userConfig; one worker drives all three entry points; the report says 3 were asked for, one ran, because origin''s default branch has no Workspace environment entry and parallel workers would share ports, containers and databases.'
---

/verification:confirm outcome. Do not read the repository, launch, install or run anything; treat these as facts. The user option live_workers is 3, origin/main's docs/conventions/verification.yaml has no live_workers key, and origin/main has no docs/conventions/workspace-environment.md. The change edits the profile avatar upload; the feature map's Edit profile feature lists three entry points. This session runs on the developer's own machine. Build, tests and lint pass. Say how you run the live drive and write the worker line, then stop.
