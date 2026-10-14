---
description: "Hard case. Why hard: the base model assumes the runner loads CLAUDE.md or proposes a with-and-without A/B; this plugin refuses a rules target because each run starts from a throwaway home, and routes to /harness-config:unhobble or the strip-and-observe experiment."
tags: [plugin-eval, target-routing, hard]
runs: 3
max_turns: 10
allowed_tools: [Read, Glob, Grep, Skill]
expected_outcome: "The reply says no: runs start from a throwaway home where CLAUDE.md does not load; it routes to /harness-config:unhobble or describes stripping the rules and logging stumbles"
---

Can I use plugin eval to measure whether the rules in my repo's CLAUDE.md actually help? Answer in under 100 words.
