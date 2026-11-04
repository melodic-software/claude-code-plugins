---
description: 'Only the corrections plugin loads, so step 1 of the preferences action must stop the run. The prompt names the target and confirms a preference, so nothing else stops a run that skips the gate before a proposal, and codify-preferences-needs-two-sessions-and-a-user-scope-target is the paired case that goes on with session-flow loaded. excerpts.jsonl holds the same made-up typed turns as that case, and the prompt names neither it nor the missing plugin, so a run that skips the gate can still find material to work from. A run needs --scaffold --allow-tools Bash Write Edit (Write and Edit are granted so the must-not graders can fail).'
tags: ['codify', 'preferences', 'no-network']
allowed_tools: [Read, Glob, Grep, Skill, Bash, Write, Edit]
max_turns: 25
timeout_seconds: 600
expected_outcome: 'The run says the preferences action needs the session-flow plugin and stops. It calls no audit-sessions skill, runs no collect, reads no transcript or store, and writes no proposal under .work/codify/.'
---

/corrections:codify preferences --scope machine --since 2026-09-01. I keep telling you the same things about how I like answers; put the ones that stick into my own instructions, my user CLAUDE.md, which does not exist yet. I confirm the date format one as it stands, if it qualifies; ask me about any other.
