---
description: "Search action: SKILL.md line 73 says '`search \"<query>\"`: search archived briefing markdown and return cited matches'. The reply returns the Northwind Cloud Agents GA item from the meeting 5 archive, labeled with meeting 5 (finds-cloud-agents), gives match context such as the HIGH tier or a recurrence count (match-context, llm), invents no item absent from the archive (no-fabrication, llm), and runs no collection: no WebFetch or WebSearch call (no-webfetch, no-websearch). Needs --scaffold --allow-tools WebFetch WebSearch so the no-collection graders can fail."
tags: [ai-briefing, generate, outcome, search, no-network]
max_turns: 10
timeout_seconds: 300
allowed_tools: [Skill, Read, Glob, Grep, WebFetch, WebSearch]
expected_outcome: "The reply returns the Northwind Cloud Agents GA item from archives/meeting-5.md, labeled meeting 5 with its HIGH tier and source link, lists no item that is not in the archive, and makes no WebFetch or WebSearch call."
---

/ai-briefing:generate search "Cloud Agents"

Treat archives/meeting-5.md in this workspace as the archived-briefing corpus to search.
