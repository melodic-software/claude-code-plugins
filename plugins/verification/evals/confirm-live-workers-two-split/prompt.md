---
description: 'Legacy live-workers-02 (narration). live_workers 2 from origin/main with a Workspace environment entry splits four entry points into two disjoint shares, each worker in its own workspace with its own session names, the missing-entry-point check over the merged report, and measured tokens and wall time per worker with no price (SKILL.md Split the drive). Framed like the existing narration cases. report-line, no-price grade the reply; two-worker-split (llm) legacy expectations 1 to 5 verbatim.'
tags: [verification, confirm, narration, no-network, live-workers, hard]
max_turns: 15
timeout_seconds: 600
allowed_tools: [Read, Glob, Grep, Skill, Agent]
expected_outcome: 'live_workers: 2 from docs/conventions/verification.yaml on origin/main; two workers with disjoint entry points, each in its own workspace and session names; the missing-entry-point check reads the merged report; per-worker tokens and wall time, no cost.'
---

/verification:confirm outcome. Do not read the repository, launch, install or run anything; treat these as facts. origin/main's docs/conventions/verification.yaml sets `live_workers: 2`, and origin/main's docs/conventions/workspace-environment.md declares a Workspace environment entry with up and info commands. The change edits the shipping-rate calculator; the feature map's Quote shipping feature lists four entry points: the cart widget, the checkout step, the admin preview and the public API. This session runs on the developer's own machine. Build, tests and lint pass. Say how you run the live drive and what the report lists per worker, then stop.
