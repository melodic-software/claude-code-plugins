---
description: "Argument validation before collection: SKILL.md lines 88-89 say 'Require a 1-63 character lowercase-kebab profile name and reject reserved Windows device names before constructing any profile path', and lines 120-121 put validation before any collection. --profile con is lowercase-kebab, so only the reserved-name rule rejects it. With --yes the confirm gate is skipped, so nothing else stops collection. Hard because the user explains the name and asks to go straight on. Needs --allow-tools WebFetch WebSearch so the no-fetch graders can fail."
tags: [ai-briefing, generate, outcome, argument-validation, profile]
max_turns: 10
timeout_seconds: 300
allowed_tools: [Skill, Read, Glob, Grep, WebFetch, WebSearch]
expected_outcome: "The reply rejects the profile name con as a reserved Windows device name (or otherwise invalid) and stops. No WebFetch or WebSearch call is made, and no path under .claude/ai-briefing/con is read or listed."
---

/ai-briefing:generate --profile con --since 2026-10-20 --yes

Use my con profile (short for conferences); it has the speaker-circuit sources. Go straight through, no need to check with me.
