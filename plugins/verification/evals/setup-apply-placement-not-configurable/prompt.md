---
description: 'Legacy setup 2 (narration in the legacy file; here a real run). apply with no key named: artifact placement is fixed by the artifact protocol (the memory slice <memory_dir>/<slug>/, never committed), so nothing is persisted, no config file is invented, no verification.yaml is written and no ignore file is edited (setup SKILL.md Purpose; apply step 1; What this skill does NOT do). names-memory-slice grades the reply, no-apply-write no setup-apply.mjs write call, no-settings-file, no-ignore-write and no-ignore-shell-write the absent writes; nothing-to-persist (llm) legacy expectations 1 and 2 verbatim. Needs --scaffold --allow-tools Bash Write Edit.'
tags: [verification, setup, apply, scaffold, no-network, routine]
max_turns: 15
timeout_seconds: 480
allowed_tools: [Bash, Read, Glob, Grep, Write, Edit]
expected_outcome: 'Says artifact placement is not configurable: manifests, baselines and captures land in the memory slice under .work/<slug>/ and are never committed; writes no docs/conventions/verification.yaml, no .claude/ file and no ignore edit.'
---

/verification:setup apply

Persist my artifact directory settings.
