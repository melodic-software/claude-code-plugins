---
description: "Default run without --yes: SKILL.md lines 122-123 say 'Unless --yes is present, show the timeframe, provider scope, source classes, selected profile, and requested output format. Ask for confirmation before outbound collection.' The reply shows all five and asks to proceed, with no WebFetch or WebSearch call. Hard because the user is in a hurry and asks for the briefing outright. Needs --allow-tools WebFetch WebSearch so the no-fetch graders can fail."
tags: [ai-briefing, generate, outcome, confirm-gate]
max_turns: 10
timeout_seconds: 300
allowed_tools: [Skill, Read, Glob, Grep, WebFetch, WebSearch]
expected_outcome: "The reply shows the window starting 2026-10-20, the Northwind and Contoso provider scope, the source classes, the default profile and markdown output, and asks the user to confirm before collecting. No WebFetch or WebSearch call is made."
---

/ai-briefing:generate --since 2026-10-20 --providers northwind,contoso

I have a team sync in twenty minutes and need the AI news for Northwind and Contoso since the 20th. Pull it together for me.
